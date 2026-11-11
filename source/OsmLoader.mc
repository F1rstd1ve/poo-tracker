import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;

// Loads OSM-Mülleimer via the paired phone. Inside the coverage of the
// Gassi-Server (Germany, Austria, Switzerland) from its Mülleimer-Kacheln
// (TileLoader, ADR 0006); elsewhere from the public Overpass API (ADR 0004).
// Nothing is loaded without the user's consent (Consent, "Teilen").
//  - radius 1 km around the position rounded to ~500 m (privacy)
//  - reload when leaving a loaded area or the area is older than 30 days
//  - answer too large for the watch (-402/-403) -> retry with 600 m, then 400 m
//  - the public servers are often overloaded (30-45 s, 502/504): any other
//    failure tries the next server after RETRY_NEXT_S; after a full round
//    without success it waits RETRY_AFTER_S. The last error code is shown on
//    the Mülleimer-Führung ("Mülleimer offline (-300)").
//  - Overpass packs all coordinates into one string per kind ("lat,lon;lat,lon…"),
//    ~22 bytes per bin: 1350 bins in central Vienna = 30 KB.
module OsmLoader {

    const SERVERS = [
        "https://overpass-api.de/api/interpreter",
        "https://lz4.overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ];
    const RADII = [1000, 600, 400];
    const RETRY_AFTER_S = 120;
    const RETRY_NEXT_S = 10;
    const RETRY_TILES_S = 60;
    // Communications error when no phone is connected.
    const CODE_NO_PHONE = -104;
    const USER_AGENT = "GassiDepot/0.1 (Garmin Connect IQ watch app)";
    const GRID_DEG = 0.005;

    const STATUS_IDLE = 0;
    const STATUS_LOADING = 1;
    const STATUS_OFFLINE = 2;
    const STATUS_OK = 3;

    var status as Number = STATUS_IDLE;
    var busy as Boolean = false;
    var radiusIndex as Number = 0;
    var serverIndex as Number = 0;
    var failedServers as Number = 0;
    var lastFailure as Number = -100000;
    var retryAfter as Number = 0;
    var lastCode as Number = 0;
    var reqLat as Float = 0.0;
    var reqLon as Float = 0.0;
    var parser as OsmParser? = null;

    function check(here as Position.Location) as Void {
        if (!Consent.online()) {
            status = STATUS_IDLE;
            return;
        }
        // One request at a time (OSM, geteilte Ebene, Beiträge).
        if (busy || SharedLoader.busy || ShareQueue.busy) {
            return;
        }
        var p = Bins.degrees(here);
        var now = Time.now().value();
        var phone = System.getDeviceSettings().phoneConnected;
        var canRequest = phone && now - lastFailure >= retryAfter;

        var tiles = TileLoader.check(p[0], p[1], canRequest);
        if (tiles == TileLoader.DONE) {
            status = STATUS_OK;
            shareStep(p, canRequest);
            return;
        }
        if (tiles == TileLoader.REQUESTED) {
            return;
        }
        if (tiles == TileLoader.NEEDED) {
            if (!phone) {
                noPhone(now);
            }
            return;
        }

        // Outside the Gassi-Server coverage: Overpass.
        if (Bins.areaCovers(p[0], p[1])) {
            status = STATUS_OK;
            shareStep(p, canRequest);
            return;
        }
        if (now - lastFailure < retryAfter) {
            return;
        }
        if (!phone) {
            noPhone(now);
            return;
        }
        // Round to a ~500 m grid so the exact position never leaves the watch.
        reqLat = (Math.round(p[0] / GRID_DEG) * GRID_DEG).toFloat();
        var lonGrid = GRID_DEG / Math.cos(Math.toRadians(p[0]));
        reqLon = (Math.round(p[1] / lonGrid) * lonGrid).toFloat();
        radiusIndex = 0;
        request();
    }

    // OSM bins complete: geteilte Ebene, then send waiting Beiträge (ADR 0006).
    function shareStep(p as Array<Float>, canRequest as Boolean) as Void {
        if (SharedLoader.check(p[0], p[1], canRequest) == SharedLoader.DONE) {
            ShareQueue.flush(canRequest);
        }
    }

    function noPhone(now as Number) as Void {
        status = STATUS_OFFLINE;
        lastCode = CODE_NO_PHONE;
        lastFailure = now;
        retryAfter = RETRY_AFTER_S;
    }

    // A tile request failed (fixed retry, the Gassi-Server is a single server).
    function failed(code as Number, retry as Number) as Void {
        System.println("tiles: load failed " + code.toString());
        busy = false;
        status = STATUS_OFFLINE;
        lastCode = code;
        lastFailure = Time.now().value();
        retryAfter = retry;
    }

    function loadedOk() as Void {
        busy = false;
        status = STATUS_OK;
        lastCode = 0;
        failedServers = 0;
        retryAfter = 0;
    }

    function request() as Void {
        busy = true;
        status = STATUS_LOADING;
        Communications.makeWebRequest(
            // The query is percent-encoded by hand: passed as a parameter, the
            // "+" (string concatenation in Overpass QL) would reach the server
            // unencoded and be read as a space -> HTTP 400.
            (SERVERS[serverIndex] as String) + "?data=" + percentEncode(query(reqLat, reqLon, RADII[radiusIndex] as Number)),
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                // Overpass answers 406 to requests without a specific User-Agent
                // (also to Android's generic "Dalvik/…").
                :headers => {"User-Agent" => USER_AGENT},
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            new Lang.Method(OsmLoader, :onResponse));
    }

    function query(lat as Float, lon as Float, radius as Number) as String {
        var around = "(around:" + radius.toString() + "," + lat.format("%.5f") + "," + lon.format("%.5f") + ")";
        return "[out:json][timeout:25];"
            + "(node[\"amenity\"=\"waste_basket\"]" + around + ";"
            + "node[\"vending\"=\"excrement_bags\"]" + around + ";)->.all;"
            + "(node.all[\"waste\"~\"dog_excrement\"];node.all[\"vending\"=\"excrement_bags\"];)->.dog;"
            + "(.all; - .dog;)->.gen;"
            + "(.dog;);make d ll=set(lat()+\",\"+lon());out;"
            + "(.gen;);make g ll=set(lat()+\",\"+lon());out;";
    }

    // RFC 3986 encoding for an ASCII string (keeps A-Z a-z 0-9 - _ . ~).
    function percentEncode(text as String) as String {
        var hex = "0123456789ABCDEF";
        var out = "";
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            var n = c.toNumber();
            if ((n >= 48 && n <= 57) || (n >= 65 && n <= 90) || (n >= 97 && n <= 122)
                    || c == '-' || c == '_' || c == '.' || c == '~') {
                out += c.toString();
            } else {
                out += "%" + hex.substring(n / 16, n / 16 + 1) + hex.substring(n % 16, n % 16 + 1);
            }
        }
        return out;
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            var parts = [] as Array<String>;
            var kinds = [] as Array<Number>;
            var elements = data["elements"];
            if (elements instanceof Array) {
                for (var i = 0; i < elements.size(); i++) {
                    var e = elements[i];
                    if (e instanceof Dictionary) {
                        var tags = e["tags"];
                        var ll = tags instanceof Dictionary ? tags["ll"] : null;
                        if (ll instanceof String && ll.length() > 0) {
                            parts.add(ll);
                            kinds.add(e["type"] == "d" ? Bins.KIND_OSM_DOG : Bins.KIND_OSM);
                        }
                    }
                }
            }
            parser = new OsmParser(parts, kinds, new Lang.Method(OsmLoader, :onParsed));
            return;
        }
        if ((code == -402 || code == -403) && radiusIndex < RADII.size() - 1) {
            radiusIndex++;
            request();
            return;
        }
        System.println("osm: load failed " + code.toString() + " server=" + serverIndex.toString());
        busy = false;
        status = STATUS_OFFLINE;
        lastCode = code;
        lastFailure = Time.now().value();
        // Next time ask the next server; wait longer after a full round.
        serverIndex = (serverIndex + 1) % SERVERS.size();
        failedServers++;
        if (failedServers < SERVERS.size()) {
            retryAfter = RETRY_NEXT_S;
        } else {
            failedServers = 0;
            retryAfter = RETRY_AFTER_S;
        }
    }

    function onParsed(p as OsmParser) as Void {
        Bins.mergeOsm(reqLat, reqLon, RADII[radiusIndex] as Number, p.outLat, p.outLon, p.outKind);
        System.println("osm: loaded " + p.outLat.size().toString() + " bins, r=" + RADII[radiusIndex].toString());
        parser = null;
        loadedOk();
        // The nearby cache is rebuilt on the next position update (mergeOsm
        // marks it dirty): doing it here would trip the watchdog.
    }
}

// Parses "lat,lon;lat,lon;…" strings in small slices on a timer, so a 30 KB
// answer never trips the watchdog.
class OsmParser {

    private const SLICE = 1500;

    var outLat as Array<Float> = [] as Array<Float>;
    var outLon as Array<Float> = [] as Array<Float>;
    var outKind as Array<Number> = [] as Array<Number>;

    private var _parts as Array<String>;
    private var _kinds as Array<Number>;
    private var _done as Method;
    private var _timer as Timer.Timer;
    private var _part as Number = 0;
    private var _pos as Number = 0;
    private var _finished as Boolean = false;
    // Values are origin + number * scale (tiles: 1e-5° from the SW corner).
    private var _oLat as Double = 0.0d;
    private var _oLon as Double = 0.0d;
    private var _scale as Double = 1.0d;

    private var _int as Number = 0;
    private var _frac as Number = 0;
    private var _div as Number = 1;
    private var _neg as Boolean = false;
    private var _inFrac as Boolean = false;
    private var _digits as Boolean = false;
    private var _lat as Double? = null;

    function initialize(parts as Array<String>, kinds as Array<Number>, done as Method) {
        _parts = parts;
        _kinds = kinds;
        _done = done;
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);
    }

    function setOffset(originLat as Double, originLon as Double, scale as Double) as Void {
        _oLat = originLat;
        _oLon = originLon;
        _scale = scale;
    }

    function tick() as Void {
        var budget = SLICE;
        while (budget > 0 && _part < _parts.size()) {
            var s = _parts[_part];
            var len = s.length();
            if (_pos >= len) {
                emit();
                _part++;
                _pos = 0;
                continue;
            }
            var end = _pos + budget;
            if (end > len) {
                end = len;
            }
            var chars = (s.substring(_pos, end) as String).toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                feed(chars[i]);
            }
            budget -= end - _pos;
            _pos = end;
        }
        if (_part >= _parts.size()) {
            // Merge in a tick of its own (watchdog budget is per callback).
            if (_finished) {
                _timer.stop();
                _done.invoke(self);
            }
            _finished = true;
        }
    }

    private function feed(c as Char) as Void {
        if (c == ',') {
            _lat = value();
            reset();
        } else if (c == ';') {
            emit();
        } else if (c == '.') {
            _inFrac = true;
        } else if (c == '-') {
            _neg = true;
        } else {
            var digit = c.toNumber() - 48;
            if (digit >= 0 && digit <= 9) {
                if (_inFrac) {
                    if (_div < 10000000) {
                        _frac = _frac * 10 + digit;
                        _div *= 10;
                    }
                } else {
                    _int = _int * 10 + digit;
                }
                _digits = true;
            }
        }
    }

    private function value() as Double {
        var v = _int.toDouble() + _frac.toDouble() / _div;
        return _neg ? -v : v;
    }

    private function emit() as Void {
        var lat = _lat;
        if (lat != null && _digits) {
            outLat.add((_oLat + lat * _scale).toFloat());
            outLon.add((_oLon + value() * _scale).toFloat());
            outKind.add(_kinds[_part]);
        }
        _lat = null;
        reset();
    }

    private function reset() as Void {
        _int = 0;
        _frac = 0;
        _div = 1;
        _neg = false;
        _inFrac = false;
        _digits = false;
    }
}
