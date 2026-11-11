import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;

// One Mülleimer near the current position (nearby cache entry).
class Bin {
    var lat as Float;
    var lon as Float;
    // Bins.KIND_GENERAL or Bins.KIND_DOG
    var kind as Number;
    // Bins.ORIGIN_OSM / ORIGIN_OWN / ORIGIN_SHARED
    var origin as Number;
    // Index into the arrays of its origin.
    var src as Number;
    // OSM bins count as confirmed.
    var confirmed as Boolean;

    function initialize(lat as Float, lon as Float, kind as Number, origin as Number, src as Number,
            confirmed as Boolean) {
        self.lat = lat;
        self.lon = lon;
        self.kind = kind;
        self.origin = origin;
        self.src = src;
        self.confirmed = confirmed;
    }

    function location() as Position.Location {
        return new Position.Location({:latitude => lat, :longitude => lon, :format => :degrees});
    }
}

// All known Mülleimer (ADR 0004, 0006):
//  - own: bins this watch added, with kind, Server-Kennung (0 = not shared yet),
//    confirmed flag and a local reference number for the Beitrag queue
//  - shared: geteilte Mülleimer of other users, per 0.4° root from the
//    Gassi-Server (SharedLoader), replaced per root
//  - OSM: from the Mülleimer-Kacheln or Overpass
// Stored as flat Float arrays (compact in Application.Storage, < 32 KB per key).
// Per-fix work only touches the "nearby" cache (bins within 600 m), which is
// rebuilt after moving 100 m or after a change. Distances use a local flat
// approximation, accurate to well under 1 % at these ranges.
module Bins {

    const KIND_GENERAL = 1;
    const KIND_DOG = 2;
    // Kinds as delivered by the OSM loaders (same values).
    const KIND_OSM = 1;
    const KIND_OSM_DOG = 2;

    const ORIGIN_OSM = 0;
    const ORIGIN_OWN = 1;
    const ORIGIN_SHARED = 2;

    // Same bin: same kind and at most this far apart (ADR 0006).
    const SAME_BIN_M = 8.0;
    const MAX_SHARED = 1500;

    const MAX_OSM = 4000;
    const NEARBY_RADIUS_M = 600.0;
    const NEARBY_REFRESH_M = 100.0;
    const DOG_PREFERENCE_M = 20.0;
    const AREA_MAX_AGE_S = 2592000; // 30 days
    const M_PER_DEG_LAT = 110540.0;
    const M_PER_DEG_LON = 111320.0;

    var ownLat as Array<Float> = [] as Array<Float>;
    var ownLon as Array<Float> = [] as Array<Float>;
    var ownKind as Array<Number> = [] as Array<Number>;
    var ownSid as Array<Number> = [] as Array<Number>;
    var ownConf as Array<Number> = [] as Array<Number>;
    var ownRef as Array<Number> = [] as Array<Number>;
    var nextRef as Number = 1;

    var shLat as Array<Float> = [] as Array<Float>;
    var shLon as Array<Float> = [] as Array<Float>;
    var shKind as Array<Number> = [] as Array<Number>;
    var shConf as Array<Number> = [] as Array<Number>;
    var shSid as Array<Number> = [] as Array<Number>;
    var shRoot as Array<String> = [] as Array<String>;
    // Geteilte Mülleimer this watch reported: never shown again here.
    var shGone as Array<Number> = [] as Array<Number>;
    var osmLat as Array<Float> = [] as Array<Float>;
    var osmLon as Array<Float> = [] as Array<Float>;
    var osmKind as Array<Number> = [] as Array<Number>;
    // Loaded OSM areas: [lat, lon, radius m, epoch s] each.
    var areas as Array<Array> = [] as Array<Array>;
    // Hidden OSM bins, keyed "lat,lon" with 5 decimals.
    var hiddenKeys as Array<String> = [] as Array<String>;

    var nearby as Array<Bin> = [] as Array<Bin>;
    var nearbyLat as Float? = null;
    var nearbyLon as Float? = null;
    var cosLat as Float = 0.66;
    var dirty as Boolean = true;
    var mapPending as Boolean = false;

    // --- persistence --------------------------------------------------------

    function load() as Void {
        ownLat = floats("own_lat");
        ownLon = floats("own_lon");
        osmLat = floats("osm_lat");
        osmLon = floats("osm_lon");
        var kinds = Application.Storage.getValue("osm_kind");
        osmKind = kinds instanceof Array ? kinds as Array<Number> : [] as Array<Number>;
        var a = Application.Storage.getValue("osm_areas");
        areas = a instanceof Array ? a as Array<Array> : [] as Array<Array>;
        var h = Application.Storage.getValue("osm_hidden");
        hiddenKeys = h instanceof Array ? h as Array<String> : [] as Array<String>;
        if (ownLat.size() != ownLon.size()) {
            ownLat = [] as Array<Float>;
            ownLon = [] as Array<Float>;
        }
        ownKind = numbers("own_kind");
        ownSid = numbers("own_sid");
        ownConf = numbers("own_conf");
        ownRef = numbers("own_ref");
        var n = Application.Storage.getValue("own_next");
        nextRef = n instanceof Number ? n : 1;
        if (ownKind.size() != ownLat.size() || ownSid.size() != ownLat.size()
                || ownConf.size() != ownLat.size() || ownRef.size() != ownLat.size()) {
            // Before Etappe B own bins had no kind: general bins, not shared yet.
            ownKind = [] as Array<Number>;
            ownSid = [] as Array<Number>;
            ownConf = [] as Array<Number>;
            ownRef = [] as Array<Number>;
            for (var i = 0; i < ownLat.size(); i++) {
                ownKind.add(KIND_GENERAL);
                ownSid.add(0);
                ownConf.add(0);
                ownRef.add(nextRef);
                nextRef++;
            }
            persistOwn();
        }

        shLat = floats("sh_lat");
        shLon = floats("sh_lon");
        shKind = numbers("sh_kind");
        shConf = numbers("sh_conf");
        shSid = numbers("sh_sid");
        var r = Application.Storage.getValue("sh_root");
        shRoot = r instanceof Array ? r as Array<String> : [] as Array<String>;
        shGone = numbers("sh_gone");
        var c = shLat.size();
        if (shLon.size() != c || shKind.size() != c || shConf.size() != c || shSid.size() != c || shRoot.size() != c) {
            clearShared();
        }
        if (osmLat.size() != osmLon.size() || osmLat.size() != osmKind.size()) {
            osmLat = [] as Array<Float>;
            osmLon = [] as Array<Float>;
            osmKind = [] as Array<Number>;
            areas = [] as Array<Array>;
        }
        dirty = true;
    }

    function floats(key as String) as Array<Float> {
        var v = Application.Storage.getValue(key);
        return v instanceof Array ? v as Array<Float> : [] as Array<Float>;
    }

    function numbers(key as String) as Array<Number> {
        var v = Application.Storage.getValue(key);
        return v instanceof Array ? v as Array<Number> : [] as Array<Number>;
    }

    function persistOwn() as Void {
        Application.Storage.setValue("own_lat", ownLat as Application.PropertyValueType);
        Application.Storage.setValue("own_lon", ownLon as Application.PropertyValueType);
        Application.Storage.setValue("own_kind", ownKind as Application.PropertyValueType);
        Application.Storage.setValue("own_sid", ownSid as Application.PropertyValueType);
        Application.Storage.setValue("own_conf", ownConf as Application.PropertyValueType);
        Application.Storage.setValue("own_ref", ownRef as Application.PropertyValueType);
        Application.Storage.setValue("own_next", nextRef);
    }

    function persistShared() as Void {
        Application.Storage.setValue("sh_lat", shLat as Application.PropertyValueType);
        Application.Storage.setValue("sh_lon", shLon as Application.PropertyValueType);
        Application.Storage.setValue("sh_kind", shKind as Application.PropertyValueType);
        Application.Storage.setValue("sh_conf", shConf as Application.PropertyValueType);
        Application.Storage.setValue("sh_sid", shSid as Application.PropertyValueType);
        Application.Storage.setValue("sh_root", shRoot as Application.PropertyValueType);
        Application.Storage.setValue("sh_gone", shGone as Application.PropertyValueType);
    }

    function clearShared() as Void {
        shLat = [] as Array<Float>;
        shLon = [] as Array<Float>;
        shKind = [] as Array<Number>;
        shConf = [] as Array<Number>;
        shSid = [] as Array<Number>;
        shRoot = [] as Array<String>;
    }

    function ownBin(i as Number) as Bin {
        return new Bin(ownLat[i], ownLon[i], ownKind[i], ORIGIN_OWN, i, ownConf[i] == 1);
    }

    function sharedBin(i as Number) as Bin {
        return new Bin(shLat[i], shLon[i], shKind[i], ORIGIN_SHARED, i, shConf[i] == 1);
    }

    function osmBin(i as Number) as Bin {
        return new Bin(osmLat[i], osmLon[i], osmKind[i], ORIGIN_OSM, i, true);
    }

    function persistOsm() as Void {
        Application.Storage.setValue("osm_lat", osmLat as Application.PropertyValueType);
        Application.Storage.setValue("osm_lon", osmLon as Application.PropertyValueType);
        Application.Storage.setValue("osm_kind", osmKind as Application.PropertyValueType);
        Application.Storage.setValue("osm_areas", areas as Application.PropertyValueType);
        Application.Storage.setValue("osm_hidden", hiddenKeys as Application.PropertyValueType);
    }

    // --- geometry (degrees) ---------------------------------------------------

    function dist(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var x = (lon2 - lon1) * cosLat * M_PER_DEG_LON;
        var y = (lat2 - lat1) * M_PER_DEG_LAT;
        return Math.sqrt(x * x + y * y).toFloat();
    }

    // Radians, 0 = north, clockwise.
    function bearing(lat as Float, lon as Float, bin as Bin) as Float {
        var x = (bin.lon - lon) * cosLat * M_PER_DEG_LON;
        var y = (bin.lat - lat) * M_PER_DEG_LAT;
        return Math.atan2(x, y).toFloat();
    }

    function degrees(loc as Position.Location) as Array<Float> {
        var d = loc.toDegrees();
        return [d[0].toFloat(), d[1].toFloat()] as Array<Float>;
    }

    // --- nearby cache -----------------------------------------------------------

    function onPosition(here as Position.Location) as Void {
        var p = degrees(here);
        var cLat = nearbyLat;
        var cLon = nearbyLon;
        if (!dirty && cLat != null && cLon != null && dist(p[0], p[1], cLat, cLon) < NEARBY_REFRESH_M) {
            // Map markers follow one position update after a rebuild, so the
            // two scans never share one callback (watchdog).
            if (mapPending) {
                mapPending = false;
                var map = Pages.mapView;
                if (map != null) {
                    map.refreshBins();
                }
            }
            return;
        }
        rebuildNearby(p[0], p[1]);
    }

    function rebuildNearby(lat as Float, lon as Float) as Void {
        cosLat = Math.cos(Math.toRadians(lat)).toFloat();
        var dLat = NEARBY_RADIUS_M / M_PER_DEG_LAT;
        var dLon = NEARBY_RADIUS_M / (M_PER_DEG_LON * cosLat);
        var list = [] as Array<Bin>;
        for (var i = 0; i < ownLat.size(); i++) {
            if ((ownLat[i] - lat).abs() <= dLat && (ownLon[i] - lon).abs() <= dLon) {
                list.add(ownBin(i));
            }
        }
        for (var i = 0; i < shLat.size(); i++) {
            if ((shLat[i] - lat).abs() <= dLat && (shLon[i] - lon).abs() <= dLon) {
                list.add(sharedBin(i));
            }
        }
        for (var i = 0; i < osmLat.size(); i++) {
            if ((osmLat[i] - lat).abs() <= dLat && (osmLon[i] - lon).abs() <= dLon) {
                list.add(osmBin(i));
            }
        }
        nearby = list;
        nearbyLat = lat;
        nearbyLon = lon;
        dirty = false;
        mapPending = true;
    }

    // --- queries (all take the current position in degrees) ------------------------

    // Target of the Mülleimer-Führung: the nearest bin, but a Hundekot-Behälter
    // wins if it is at most 20 m farther. Falls back to a full scan when nothing
    // is in the nearby cache.
    function target(lat as Float, lon as Float) as Bin? {
        var best = null;
        var bestD = 0.0;
        var dog = null;
        var dogD = 0.0;
        for (var i = 0; i < nearby.size(); i++) {
            var b = nearby[i];
            var d = dist(lat, lon, b.lat, b.lon);
            if (best == null || d < bestD) {
                best = b;
                bestD = d;
            }
            if (b.kind == KIND_DOG && (dog == null || d < dogD)) {
                dog = b;
                dogD = d;
            }
        }
        if (best == null) {
            return nearestAnywhere(lat, lon);
        }
        if (dog != null && dogD <= bestD + DOG_PREFERENCE_M) {
            return dog;
        }
        return best;
    }

    function nearestAnywhere(lat as Float, lon as Float) as Bin? {
        var best = null;
        var bestD = 0.0;
        var bestOrigin = -1;
        var bestIndex = 0;
        for (var i = 0; i < ownLat.size(); i++) {
            var d = dist(lat, lon, ownLat[i], ownLon[i]);
            if (bestOrigin < 0 || d < bestD) {
                bestOrigin = ORIGIN_OWN;
                bestIndex = i;
                bestD = d;
            }
        }
        for (var i = 0; i < shLat.size(); i++) {
            var d = dist(lat, lon, shLat[i], shLon[i]);
            if (bestOrigin < 0 || d < bestD) {
                bestOrigin = ORIGIN_SHARED;
                bestIndex = i;
                bestD = d;
            }
        }
        for (var i = 0; i < osmLat.size(); i++) {
            var d = dist(lat, lon, osmLat[i], osmLon[i]);
            if (bestOrigin < 0 || d < bestD) {
                bestOrigin = ORIGIN_OSM;
                bestIndex = i;
                bestD = d;
            }
        }
        if (bestOrigin == ORIGIN_OWN) {
            best = ownBin(bestIndex);
        } else if (bestOrigin == ORIGIN_SHARED) {
            best = sharedBin(bestIndex);
        } else if (bestOrigin == ORIGIN_OSM) {
            best = osmBin(bestIndex);
        }
        return best;
    }

    // Distance to the nearest nearby bin, or -1.
    function nearestDistance(lat as Float, lon as Float) as Float {
        var bestD = -1.0;
        for (var i = 0; i < nearby.size(); i++) {
            var d = dist(lat, lon, nearby[i].lat, nearby[i].lon);
            if (bestD < 0 || d < bestD) {
                bestD = d;
            }
        }
        return bestD;
    }

    function within(lat as Float, lon as Float, radius as Float) as Array<Bin> {
        var result = [] as Array<Bin>;
        for (var i = 0; i < nearby.size(); i++) {
            if (dist(lat, lon, nearby[i].lat, nearby[i].lon) <= radius) {
                result.add(nearby[i]);
            }
        }
        return result;
    }

    // Up to `n` nearest bins within `radius`, nearest first.
    // Single pass with a small sorted top-n list (keeps the watchdog happy with
    // hundreds of nearby bins).
    function nearestN(lat as Float, lon as Float, n as Number, radius as Float) as Array<Bin> {
        var bins = [] as Array<Bin>;
        var ds = [] as Array<Float>;
        for (var i = 0; i < nearby.size(); i++) {
            var b = nearby[i];
            var d = dist(lat, lon, b.lat, b.lon);
            if (d > radius || (ds.size() >= n && d >= ds[n - 1])) {
                continue;
            }
            if (ds.size() >= n) {
                // Overwrite the worst entry, then bubble into place.
                bins[n - 1] = b;
                ds[n - 1] = d;
            } else {
                bins.add(b);
                ds.add(d);
            }
            var k = ds.size() - 1;
            while (k > 0 && ds[k - 1] > ds[k]) {
                var td = ds[k - 1];
                ds[k - 1] = ds[k];
                ds[k] = td;
                var tb = bins[k - 1];
                bins[k - 1] = bins[k];
                bins[k] = tb;
                k--;
            }
        }
        return bins;
    }

    // Nearest bin of `kind` within `radius` (nearby cache), or null.
    function sameKindWithin(lat as Float, lon as Float, kind as Number, radius as Float) as Bin? {
        var best = null;
        var bestD = radius;
        for (var i = 0; i < nearby.size(); i++) {
            var b = nearby[i];
            if (b.kind != kind) {
                continue;
            }
            var d = dist(lat, lon, b.lat, b.lon);
            if (d <= bestD) {
                best = b;
                bestD = d;
            }
        }
        return best;
    }

    // --- changes --------------------------------------------------------------

    // Adds an own bin and returns its local reference number.
    function addOwn(loc as Position.Location, kind as Number) as Number {
        var p = degrees(loc);
        var ref = nextRef;
        nextRef++;
        ownLat.add(p[0]);
        ownLon.add(p[1]);
        ownKind.add(kind);
        ownSid.add(0);
        ownConf.add(0);
        ownRef.add(ref);
        persistOwn();
        rebuildNearby(p[0], p[1]);
        return ref;
    }

    // Own bins are deleted, geteilte and OSM bins disappear on this watch
    // (the Meldung for everyone is sent by BinActions).
    function remove(bin as Bin) as Void {
        var i = bin.src;
        if (bin.origin == ORIGIN_OWN) {
            ownLat = without(ownLat, i) as Array<Float>;
            ownLon = without(ownLon, i) as Array<Float>;
            ownKind = without(ownKind, i) as Array<Number>;
            ownSid = without(ownSid, i) as Array<Number>;
            ownConf = without(ownConf, i) as Array<Number>;
            ownRef = without(ownRef, i) as Array<Number>;
            persistOwn();
        } else if (bin.origin == ORIGIN_SHARED) {
            shGone.add(shSid[i]);
            removeShared(i);
            persistShared();
        } else {
            hiddenKeys.add(key(osmLat[i], osmLon[i]));
            removeOsm(i);
            persistOsm();
        }
        refresh();
    }

    function removeShared(i as Number) as Void {
        shLat = without(shLat, i) as Array<Float>;
        shLon = without(shLon, i) as Array<Float>;
        shKind = without(shKind, i) as Array<Number>;
        shConf = without(shConf, i) as Array<Number>;
        shSid = without(shSid, i) as Array<Number>;
        shRoot = without(shRoot, i) as Array<String>;
    }

    function removeOsm(i as Number) as Void {
        osmLat = without(osmLat, i) as Array<Float>;
        osmLon = without(osmLon, i) as Array<Float>;
        osmKind = without(osmKind, i) as Array<Number>;
    }

    // Rebuild the nearby cache at the last position after a change.
    function refresh() as Void {
        dirty = true;
        var cLat = nearbyLat;
        var cLon = nearbyLon;
        if (cLat != null && cLon != null) {
            rebuildNearby(cLat, cLon);
        }
    }

    function ownIndex(ref as Number) as Number {
        return ownRef.indexOf(ref);
    }

    // The Gassi-Server stored an own bin: remember its Server-Kennung. If it
    // confirmed an existing geteilter Mülleimer, that one is now ours.
    function setOwnSid(ref as Number, sid as Number, confirmed as Boolean) as Void {
        var i = ownRef.indexOf(ref);
        if (i < 0) {
            return;
        }
        ownSid[i] = sid;
        ownConf[i] = confirmed ? 1 : 0;
        persistOwn();
        var j = shSid.indexOf(sid);
        if (j >= 0) {
            removeShared(j);
            persistShared();
        }
        refresh();
    }

    // "Entsorgt" at a geteilter Mülleimer of another user (Beitrag sent by Disposal).
    function confirmShared(i as Number) as Void {
        shConf[i] = 1;
        persistShared();
        refresh();
    }

    // Fresh geteilte Ebene of one root: replaces its geteilte Mülleimer and
    // hides OSM bins that were reported by 2 users (hLat/hLon/hKind).
    function mergeShared(root as String, lat as Array<Float>, lon as Array<Float>, kind as Array<Number>,
            conf as Array<Number>, sid as Array<Number>,
            hLat as Array<Float>, hLon as Array<Float>, hKind as Array<Number>) as Void {
        var keep = [] as Array<Number>;
        for (var i = 0; i < shRoot.size(); i++) {
            if (!shRoot[i].equals(root)) {
                keep.add(i);
            }
        }
        var la = [] as Array<Float>;
        var lo = [] as Array<Float>;
        var ki = [] as Array<Number>;
        var co = [] as Array<Number>;
        var si = [] as Array<Number>;
        var ro = [] as Array<String>;
        for (var k = 0; k < keep.size(); k++) {
            var i = keep[k];
            la.add(shLat[i]);
            lo.add(shLon[i]);
            ki.add(shKind[i]);
            co.add(shConf[i]);
            si.add(shSid[i]);
            ro.add(shRoot[i]);
        }
        var ownChanged = false;
        for (var i = 0; i < lat.size() && la.size() < MAX_SHARED; i++) {
            var own = ownSid.indexOf(sid[i]);
            if (own >= 0) {
                // Our own bin: only take over "bestätigt".
                if (ownConf[own] != conf[i]) {
                    ownConf[own] = conf[i];
                    ownChanged = true;
                }
                continue;
            }
            if (shGone.indexOf(sid[i]) >= 0) {
                continue;
            }
            la.add(lat[i]);
            lo.add(lon[i]);
            ki.add(kind[i]);
            co.add(conf[i]);
            si.add(sid[i]);
            ro.add(root);
        }
        shLat = la;
        shLon = lo;
        shKind = ki;
        shConf = co;
        shSid = si;
        shRoot = ro;
        persistShared();
        if (ownChanged) {
            persistOwn();
        }

        var osmChanged = false;
        for (var h = 0; h < hLat.size(); h++) {
            cosLat = Math.cos(Math.toRadians(hLat[h])).toFloat();
            for (var i = osmLat.size() - 1; i >= 0; i--) {
                if (osmKind[i] == hKind[h] && (osmLat[i] - hLat[h]).abs() < 0.0001
                        && dist(hLat[h], hLon[h], osmLat[i], osmLon[i]) <= 3.0) {
                    hiddenKeys.add(key(osmLat[i], osmLon[i]));
                    removeOsm(i);
                    osmChanged = true;
                }
            }
        }
        if (osmChanged) {
            persistOsm();
        }
        refresh();
    }

    // Own bins the Gassi-Server knows.
    function sharedOwnCount() as Number {
        var n = 0;
        for (var i = 0; i < ownSid.size(); i++) {
            if (ownSid[i] != 0) {
                n++;
            }
        }
        return n;
    }

    function without(arr as Array, index as Number) as Array {
        return arr.slice(0, index).addAll(arr.slice(index + 1, null));
    }

    function key(lat as Float, lon as Float) as String {
        return lat.format("%.5f") + "," + lon.format("%.5f");
    }

    // --- OSM areas --------------------------------------------------------------

    // Is `lat/lon` inside a fresh loaded area (with margin, spec: reload after 1 km)?
    function areaCovers(lat as Float, lon as Float) as Boolean {
        var now = Time.now().value();
        for (var i = 0; i < areas.size(); i++) {
            var a = areas[i];
            var r = (a[2] as Number).toFloat();
            var margin = r - 500.0 > r * 0.5 ? r - 500.0 : r * 0.5;
            if (now - (a[3] as Number) < AREA_MAX_AGE_S
                    && dist(lat, lon, a[0] as Float, a[1] as Float) <= margin) {
                return true;
            }
        }
        return false;
    }

    // Replace the OSM bins inside a Mülleimer-Kachel with its fresh content.
    // Returns true if old bins had to be dropped to stay below MAX_OSM.
    function mergeRect(lat0 as Float, lon0 as Float, lat1 as Float, lon1 as Float,
            newLat as Array<Float>, newLon as Array<Float>, newKind as Array<Number>) as Boolean {
        cosLat = Math.cos(Math.toRadians(lat0)).toFloat();
        var lat = [] as Array<Float>;
        var lon = [] as Array<Float>;
        var kind = [] as Array<Number>;
        for (var i = 0; i < osmLat.size(); i++) {
            var la = osmLat[i];
            var lo = osmLon[i];
            if (la < lat0 || la >= lat1 || lo < lon0 || lo >= lon1) {
                lat.add(la);
                lon.add(lo);
                kind.add(osmKind[i]);
            }
        }
        var trimmed = appendNew(lat, lon, kind, newLat, newLon, newKind);
        persistOsm();
        dirty = true;
        return trimmed;
    }

    // Adds fresh OSM bins (except hidden ones) and keeps at most MAX_OSM,
    // dropping the oldest. Sets osmLat/osmLon/osmKind. True if trimmed.
    function appendNew(lat as Array<Float>, lon as Array<Float>, kind as Array<Number>,
            newLat as Array<Float>, newLon as Array<Float>, newKind as Array<Number>) as Boolean {
        var anyHidden = hiddenKeys.size() > 0;
        for (var i = 0; i < newLat.size(); i++) {
            if (!anyHidden || hiddenKeys.indexOf(key(newLat[i], newLon[i])) < 0) {
                lat.add(newLat[i]);
                lon.add(newLon[i]);
                kind.add(newKind[i]);
            }
        }
        var trimmed = false;
        if (lat.size() > MAX_OSM) {
            // Keep the newest (they were appended last).
            var from = lat.size() - MAX_OSM;
            lat = lat.slice(from, null);
            lon = lon.slice(from, null);
            kind = kind.slice(from, null);
            trimmed = true;
        }
        osmLat = lat;
        osmLon = lon;
        osmKind = kind;
        return trimmed;
    }

    // Replace the OSM bins inside the loaded circle with the fresh result.
    function mergeOsm(cLat as Float, cLon as Float, radius as Number,
            newLat as Array<Float>, newLon as Array<Float>, newKind as Array<Number>) as Void {
        cosLat = Math.cos(Math.toRadians(cLat)).toFloat();
        var lat = [] as Array<Float>;
        var lon = [] as Array<Float>;
        var kind = [] as Array<Number>;
        for (var i = 0; i < osmLat.size(); i++) {
            if (dist(cLat, cLon, osmLat[i], osmLon[i]) > radius) {
                lat.add(osmLat[i]);
                lon.add(osmLon[i]);
                kind.add(osmKind[i]);
            }
        }
        appendNew(lat, lon, kind, newLat, newLon, newKind);

        var now = Time.now().value();
        var keep = [] as Array<Array>;
        for (var i = 0; i < areas.size(); i++) {
            if (now - (areas[i][3] as Number) < AREA_MAX_AGE_S && keep.size() < 30) {
                keep.add(areas[i]);
            }
        }
        keep.add([cLat, cLon, radius, now]);
        areas = keep;
        persistOsm();
        dirty = true;
    }

    function count() as Number {
        return ownLat.size() + shLat.size() + osmLat.size();
    }
}
