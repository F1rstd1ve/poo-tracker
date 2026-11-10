import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;

// One Mülleimer near the current position (nearby cache entry).
class Bin {
    var lat as Float;
    var lon as Float;
    var kind as Number;
    // Where it lives: >= 0 index into the OSM arrays, < 0 own bin -(index + 1).
    var src as Number;

    function initialize(lat as Float, lon as Float, kind as Number, src as Number) {
        self.lat = lat;
        self.lon = lon;
        self.kind = kind;
        self.src = src;
    }

    function location() as Position.Location {
        return new Position.Location({:latitude => lat, :longitude => lon, :format => :degrees});
    }
}

// All known Mülleimer: eigene Mülleimer + OSM-Mülleimer (ADR 0004).
// Stored as flat Float arrays (compact in Application.Storage, < 32 KB per key).
// Per-fix work only touches the "nearby" cache (bins within 600 m), which is
// rebuilt after moving 100 m or after a change. Distances use a local flat
// approximation, accurate to well under 1 % at these ranges.
module Bins {

    const KIND_OWN = 0;
    const KIND_OSM = 1;
    const KIND_OSM_DOG = 2;

    const MAX_OSM = 4000;
    const NEARBY_RADIUS_M = 600.0;
    const NEARBY_REFRESH_M = 100.0;
    const DOG_PREFERENCE_M = 20.0;
    const AREA_MAX_AGE_S = 2592000; // 30 days
    const M_PER_DEG_LAT = 110540.0;
    const M_PER_DEG_LON = 111320.0;

    var ownLat as Array<Float> = [] as Array<Float>;
    var ownLon as Array<Float> = [] as Array<Float>;
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

    function persistOwn() as Void {
        Application.Storage.setValue("own_lat", ownLat as Application.PropertyValueType);
        Application.Storage.setValue("own_lon", ownLon as Application.PropertyValueType);
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
                list.add(new Bin(ownLat[i], ownLon[i], KIND_OWN, -(i + 1)));
            }
        }
        for (var i = 0; i < osmLat.size(); i++) {
            if ((osmLat[i] - lat).abs() <= dLat && (osmLon[i] - lon).abs() <= dLon) {
                list.add(new Bin(osmLat[i], osmLon[i], osmKind[i], i));
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
            if (b.kind == KIND_OSM_DOG && (dog == null || d < dogD)) {
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
        for (var i = 0; i < ownLat.size(); i++) {
            var d = dist(lat, lon, ownLat[i], ownLon[i]);
            if (best == null || d < bestD) {
                best = new Bin(ownLat[i], ownLon[i], KIND_OWN, -(i + 1));
                bestD = d;
            }
        }
        for (var i = 0; i < osmLat.size(); i++) {
            var d = dist(lat, lon, osmLat[i], osmLon[i]);
            if (best == null || d < bestD) {
                best = new Bin(osmLat[i], osmLon[i], osmKind[i], i);
                bestD = d;
            }
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

    function hasBinWithin(lat as Float, lon as Float, radius as Float) as Boolean {
        for (var i = 0; i < nearby.size(); i++) {
            if (dist(lat, lon, nearby[i].lat, nearby[i].lon) <= radius) {
                return true;
            }
        }
        return false;
    }

    // --- changes --------------------------------------------------------------

    function addOwn(loc as Position.Location) as Void {
        var p = degrees(loc);
        ownLat.add(p[0]);
        ownLon.add(p[1]);
        persistOwn();
        rebuildNearby(p[0], p[1]);
    }

    // Own bins are deleted, OSM bins hidden on this watch only.
    function remove(bin as Bin) as Void {
        if (bin.src < 0) {
            var i = -bin.src - 1;
            ownLat = without(ownLat, i) as Array<Float>;
            ownLon = without(ownLon, i) as Array<Float>;
            persistOwn();
        } else {
            var i = bin.src;
            hiddenKeys.add(key(osmLat[i], osmLon[i]));
            osmLat = without(osmLat, i) as Array<Float>;
            osmLon = without(osmLon, i) as Array<Float>;
            osmKind = without(osmKind, i) as Array<Number>;
            persistOsm();
        }
        dirty = true;
        var cLat = nearbyLat;
        var cLon = nearbyLon;
        if (cLat != null && cLon != null) {
            rebuildNearby(cLat, cLon);
        }
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
        return ownLat.size() + osmLat.size();
    }
}
