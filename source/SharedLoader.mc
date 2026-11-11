import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Loads the geteilte Ebene from the Gassi-Server (ADR 0006, Etappe B):
// per 0.4° root (same grid as the Mülleimer-Kacheln) the geteilten Mülleimer
// of all users and the OSM bins hidden by 2 Meldungen. Every root within
// TileLoader.LOAD_M of the position is loaded, valid for 1 hour (the server
// caches it for the same time). Runs after the OSM bins are complete, so
// hidden OSM bins are already there to be removed.
//   {"b": "id,k,f,dlat,dlon;…", "h": "k,dlat,dlon;…"}  (1e-5° from the root's SW corner)
module SharedLoader {

    const PATH = "/api/v1/s/";
    const MAX_AGE_S = 3600;
    const RETRY_S = 120;

    const DONE = 1;
    const REQUESTED = 2;
    const NEEDED = 3;

    // root key -> epoch s
    var loaded as Dictionary<String, Number> = {} as Dictionary<String, Number>;
    var busy as Boolean = false;
    var retryAt as Number = 0;
    var reqRoot as String = "";
    var reqLat0 as Double = 0.0d;
    var reqLon0 as Double = 0.0d;

    function load() as Void {
        var l = Application.Storage.getValue("sh_loaded");
        loaded = l instanceof Dictionary ? l as Dictionary<String, Number> : {} as Dictionary<String, Number>;
    }

    function check(lat as Float, lon as Float, canRequest as Boolean) as Number {
        if (busy) {
            return REQUESTED;
        }
        var now = Time.now().value();
        var latD = lat.toDouble();
        var lonD = lon.toDouble();
        var cos = Math.cos(Math.toRadians(lat));
        var hLat = TileLoader.LOAD_M / Bins.M_PER_DEG_LAT;
        var hLon = TileLoader.LOAD_M / (Bins.M_PER_DEG_LON * cos);
        for (var ri = TileLoader.rootI(latD - hLat); ri <= TileLoader.rootI(latD + hLat); ri++) {
            for (var rj = TileLoader.rootJ(lonD - hLon); rj <= TileLoader.rootJ(lonD + hLon); rj++) {
                var key = TileLoader.rootKey(ri, rj);
                var at = loaded[key];
                if (at != null && now - at < MAX_AGE_S) {
                    continue;
                }
                if (!canRequest || now < retryAt) {
                    return NEEDED;
                }
                request(key, ri, rj);
                return REQUESTED;
            }
        }
        return DONE;
    }

    function request(key as String, ri as Number, rj as Number) as Void {
        busy = true;
        reqRoot = key;
        reqLat0 = ri * TileLoader.ROOT_DEG - 90.0d;
        reqLon0 = rj * TileLoader.ROOT_DEG - 180.0d;
        Communications.makeWebRequest(ServerConfig.BASE + PATH + key, null, TileLoader.options(),
            new Lang.Method(SharedLoader, :onResponse));
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        busy = false;
        if (code != 200 || !(data instanceof Dictionary)) {
            System.println("shared: failed " + code.toString());
            retryAt = Time.now().value() + RETRY_S;
            return;
        }
        var lat = [] as Array<Float>;
        var lon = [] as Array<Float>;
        var kind = [] as Array<Number>;
        var conf = [] as Array<Number>;
        var sid = [] as Array<Number>;
        var b = data["b"];
        if (b instanceof String) {
            var rows = split(b, ";");
            for (var i = 0; i < rows.size() && i < Bins.MAX_SHARED; i++) {
                var f = split(rows[i], ",");
                if (f.size() != 5) {
                    continue;
                }
                sid.add(f[0].toNumber() as Number);
                kind.add(f[1].toNumber() as Number);
                conf.add(f[2].toNumber() as Number);
                lat.add((reqLat0 + (f[3].toNumber() as Number) * TileLoader.UNIT).toFloat());
                lon.add((reqLon0 + (f[4].toNumber() as Number) * TileLoader.UNIT).toFloat());
            }
        }
        var hLat = [] as Array<Float>;
        var hLon = [] as Array<Float>;
        var hKind = [] as Array<Number>;
        var h = data["h"];
        if (h instanceof String) {
            var rows = split(h, ";");
            for (var i = 0; i < rows.size() && i < 200; i++) {
                var f = split(rows[i], ",");
                if (f.size() != 3) {
                    continue;
                }
                hKind.add(f[0].toNumber() as Number);
                hLat.add((reqLat0 + (f[1].toNumber() as Number) * TileLoader.UNIT).toFloat());
                hLon.add((reqLon0 + (f[2].toNumber() as Number) * TileLoader.UNIT).toFloat());
            }
        }
        Bins.mergeShared(reqRoot, lat, lon, kind, conf, sid, hLat, hLon, hKind);
        loaded[reqRoot] = Time.now().value();
        Application.Storage.setValue("sh_loaded", loaded as Application.PropertyValueType);
        System.println("shared: loaded " + reqRoot + " bins=" + lat.size().toString() + " hidden=" + hLat.size().toString());
    }

    // Non-empty parts of `text` separated by the character `sep` (one pass).
    function split(text as String, sep as String) as Array<String> {
        var parts = [] as Array<String>;
        var chars = text.toCharArray();
        var s = sep.toCharArray()[0];
        var start = 0;
        for (var i = 0; i <= chars.size(); i++) {
            if (i == chars.size() || chars[i] == s) {
                if (i > start) {
                    parts.add(text.substring(start, i) as String);
                }
                start = i + 1;
            }
        }
        return parts;
    }
}
