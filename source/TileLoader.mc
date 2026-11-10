import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Loads Mülleimer-Kacheln from the Gassi-Server (ADR 0006, format t1, see
// docs/spec-server.md and pipeline/build_tiles.py):
//  - fixed root grid of 0.4°, each root a quadtree described by i.json
//    ('1' split into SW/SE/NW/NE, '0' leaf with bins, '-' empty leaf)
//  - leaves hold "dlat,dlon;" in 1e-5° relative to their SW corner
// Loads every leaf within LOAD_M of the position, one request at a time.
// A root without i.json (404) is outside the coverage: OsmLoader then falls
// back to Overpass. Shares busy/status/error handling with OsmLoader.
module TileLoader {

    const PATH = "/t1/";
    const ROOT_DEG = 0.4d;
    const UNIT = 0.00001d;
    const LOAD_M = 500.0;
    const RECHECK_M = 100.0;
    const MAX_AGE_S = 2592000;       // 30 days
    const UNCOVERED_AGE_S = 604800;  // 7 days

    // check() results
    const UNCOVERED = 0;   // not on the Gassi-Server -> Overpass
    const DONE = 1;        // everything around is loaded
    const REQUESTED = 2;   // a request is running
    const NEEDED = 3;      // something is missing but no request was allowed

    // root key -> [preorder ("" = uncovered), epoch s]
    var index as Dictionary<String, Array> = {} as Dictionary<String, Array>;
    // leaf key -> epoch s
    var loaded as Dictionary<String, Number> = {} as Dictionary<String, Number>;

    // What check() last found missing while no request was allowed:
    // [root key, leaf array or null for the index] (diagnostics/tests).
    var need as Array? = null;

    var doneLat as Float? = null;
    var doneLon as Float? = null;

    var reqRoot as String = "";
    var reqLeaf as String = "";
    var reqLat0 as Double = 0.0d;
    var reqLon0 as Double = 0.0d;
    var reqSize as Double = 0.0d;

    // walk state
    var _chars as Array<Char> = [] as Array<Char>;
    var _pos as Number = 0;
    var _box as Array<Double> = [] as Array<Double>;
    var _now as Number = 0;
    var _found as Array? = null;

    function load() as Void {
        var i = Application.Storage.getValue("tile_idx");
        index = i instanceof Dictionary ? i as Dictionary<String, Array> : {} as Dictionary<String, Array>;
        var l = Application.Storage.getValue("tile_loaded");
        loaded = l instanceof Dictionary ? l as Dictionary<String, Number> : {} as Dictionary<String, Number>;
    }

    function persist() as Void {
        Application.Storage.setValue("tile_idx", index as Application.PropertyValueType);
        Application.Storage.setValue("tile_loaded", loaded as Application.PropertyValueType);
    }

    function rootKey(ri as Number, rj as Number) as String {
        return ri.toString() + "_" + rj.toString();
    }

    function rootI(lat as Double) as Number {
        return Math.floor((lat + 90.0d) / ROOT_DEG).toNumber();
    }

    function rootJ(lon as Double) as Number {
        return Math.floor((lon + 180.0d) / ROOT_DEG).toNumber();
    }

    // canRequest: phone connected and no back-off running.
    function check(lat as Float, lon as Float, canRequest as Boolean) as Number {
        var now = Time.now().value();
        var latD = lat.toDouble();
        var lonD = lon.toDouble();
        var home = rootKey(rootI(latD), rootJ(lonD));
        var homeEntry = index[home];
        if (homeEntry != null && fresh(homeEntry, now) && (homeEntry[0] as String).equals("")) {
            return UNCOVERED;
        }
        // Nothing new to do until we moved RECHECK_M from the last complete check.
        var dLat = doneLat;
        var dLon = doneLon;
        if (dLat != null && dLon != null && Bins.dist(lat, lon, dLat, dLon) < RECHECK_M) {
            return DONE;
        }

        var cos = Math.cos(Math.toRadians(lat));
        var hLat = LOAD_M / Bins.M_PER_DEG_LAT;
        var hLon = LOAD_M / (Bins.M_PER_DEG_LON * cos);
        _box = [latD - hLat, lonD - hLon, latD + hLat, lonD + hLon] as Array<Double>;
        _now = now;

        for (var ri = rootI(_box[0]); ri <= rootI(_box[2]); ri++) {
            for (var rj = rootJ(_box[1]); rj <= rootJ(_box[3]); rj++) {
                var key = rootKey(ri, rj);
                var entry = index[key];
                if (entry == null || !fresh(entry, now)) {
                    if (!canRequest) {
                        need = [key, null];
                        return NEEDED;
                    }
                    requestIndex(key);
                    return REQUESTED;
                }
                var tree = entry[0] as String;
                if (tree.equals("")) {
                    continue;
                }
                var leaf = missingLeaf(key, ri, rj, tree);
                if (leaf != null) {
                    if (!canRequest) {
                        need = [key, leaf];
                        return NEEDED;
                    }
                    requestLeaf(key, leaf);
                    return REQUESTED;
                }
            }
        }
        doneLat = lat;
        doneLon = lon;
        return DONE;
    }

    function fresh(entry as Array, now as Number) as Boolean {
        var age = (entry[0] as String).equals("") ? UNCOVERED_AGE_S : MAX_AGE_S;
        return now - (entry[1] as Number) < age;
    }

    // --- quadtree walk --------------------------------------------------------

    // First leaf of this root that intersects _box and is not loaded (fresh):
    // [path, lat0, lon0, size] or null.
    function missingLeaf(key as String, ri as Number, rj as Number, tree as String) as Array? {
        _chars = tree.toCharArray();
        _pos = 0;
        _found = null;
        walk(key, "", ri * ROOT_DEG - 90.0d, rj * ROOT_DEG - 180.0d, ROOT_DEG);
        return _found;
    }

    function walk(key as String, path as String, lat0 as Double, lon0 as Double, size as Double) as Void {
        if (_pos >= _chars.size()) {
            return;
        }
        var c = _chars[_pos];
        _pos++;
        if (c == '1') {
            var half = size / 2.0d;
            walk(key, path + "0", lat0, lon0, half);
            walk(key, path + "1", lat0, lon0 + half, half);
            walk(key, path + "2", lat0 + half, lon0, half);
            walk(key, path + "3", lat0 + half, lon0 + half, half);
            return;
        }
        if (c != '0' || _found != null) {
            return;
        }
        if (lat0 > _box[2] || lat0 + size < _box[0] || lon0 > _box[3] || lon0 + size < _box[1]) {
            return;
        }
        var name = path.equals("") ? "r" : path;
        var at = loaded[key + "/" + name];
        if (at != null && _now - at < MAX_AGE_S) {
            return;
        }
        _found = [name, lat0, lon0, size];
    }

    // --- requests --------------------------------------------------------------

    function options() as Dictionary {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {"User-Agent" => OsmLoader.USER_AGENT},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    function requestIndex(key as String) as Void {
        OsmLoader.busy = true;
        OsmLoader.status = OsmLoader.STATUS_LOADING;
        reqRoot = key;
        Communications.makeWebRequest(ServerConfig.BASE + PATH + key + "/i.json", null, options(),
            new Lang.Method(TileLoader, :onIndex));
    }

    function onIndex(code as Number, data as Dictionary or String or Null) as Void {
        var now = Time.now().value();
        if (code == 200 && data instanceof Dictionary && data["s"] instanceof String) {
            index[reqRoot] = [data["s"] as String, now];
        } else if (code == 404) {
            index[reqRoot] = ["", now];
        } else {
            OsmLoader.failed(code, OsmLoader.RETRY_TILES_S);
            return;
        }
        persist();
        OsmLoader.busy = false;
        doneLat = null;
    }

    function requestLeaf(key as String, leaf as Array) as Void {
        OsmLoader.busy = true;
        OsmLoader.status = OsmLoader.STATUS_LOADING;
        reqRoot = key;
        reqLeaf = leaf[0] as String;
        reqLat0 = leaf[1] as Double;
        reqLon0 = leaf[2] as Double;
        reqSize = leaf[3] as Double;
        Communications.makeWebRequest(ServerConfig.BASE + PATH + key + "/" + reqLeaf + ".json", null, options(),
            new Lang.Method(TileLoader, :onLeaf));
    }

    function onLeaf(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            var d = data["d"];
            var g = data["g"];
            var parts = [d instanceof String ? d : "", g instanceof String ? g : ""] as Array<String>;
            var kinds = [Bins.KIND_OSM_DOG, Bins.KIND_OSM] as Array<Number>;
            var p = new OsmParser(parts, kinds, new Lang.Method(TileLoader, :onParsed));
            p.setOffset(reqLat0, reqLon0, UNIT);
            OsmLoader.parser = p;
            return;
        }
        if (code == 404) {
            // The tile structure changed with the weekly update: reload the index.
            index.remove(reqRoot);
            persist();
            OsmLoader.busy = false;
            doneLat = null;
            return;
        }
        OsmLoader.failed(code, OsmLoader.RETRY_TILES_S);
    }

    function onParsed(p as OsmParser) as Void {
        var trimmed = Bins.mergeRect(reqLat0.toFloat(), reqLon0.toFloat(), (reqLat0 + reqSize).toFloat(),
            (reqLon0 + reqSize).toFloat(), p.outLat, p.outLon, p.outKind);
        if (trimmed) {
            // Old bins were dropped to stay below Bins.MAX_OSM: their tiles
            // must be loaded again when we get there.
            loaded = {} as Dictionary<String, Number>;
        }
        loaded[reqRoot + "/" + reqLeaf] = Time.now().value();
        persist();
        System.println("tiles: loaded " + reqRoot + "/" + reqLeaf + " bins=" + p.outLat.size().toString());
        OsmLoader.parser = null;
        OsmLoader.loadedOk();
        doneLat = null;
    }
}
