import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Beiträge for the Gassi-Server (ADR 0006, docs/spec-server.md, Etappe B):
// added bins, Meldungen, confirmations by "Entsorgt" and deleting own
// unconfirmed bins. Kept in storage until the server accepted them; sent in
// batches of up to 10 when the phone is connected and nothing else loads.
// Needs the consent "Teilen"; the anonymous Kennung is created with it and
// forgotten when sharing is switched off.
module ShareQueue {

    const PATH = "/api/v1/c";
    const BATCH = 10;
    const RETRY_ERROR_S = 120;
    const RETRY_LIMIT_S = 21600; // 6 h ("limit" / "far": try again later)
    const MAX_ITEMS = 300;

    // Item fields
    const F_TYPE = 0;   // "a" add, "r" Meldung, "f" confirm, "x" delete
    const F_KIND = 1;
    const F_LAT = 2;
    const F_LON = 3;
    const F_IMP = 4;
    const F_SID = 5;
    const F_REF = 6;

    var items as Array<Array> = [] as Array<Array>;
    var sending as Array<Array> = [] as Array<Array>;
    var busy as Boolean = false;
    var retryAt as Number = 0;
    // Last server answer (HTTP code or Connect IQ error), for the start menu.
    var lastCode as Number = 0;

    function load() as Void {
        var q = Application.Storage.getValue("share_q");
        items = q instanceof Array ? q as Array<Array> : [] as Array<Array>;
    }

    function persist() as Void {
        Application.Storage.setValue("share_q", items as Application.PropertyValueType);
    }

    function size() as Number {
        return items.size();
    }

    // --- Kennung ------------------------------------------------------------------

    function uid() as String? {
        var u = Application.Storage.getValue("share_uid");
        return u instanceof String ? u : null;
    }

    function ensureUid() as Void {
        if (uid() != null) {
            return;
        }
        Math.srand(Time.now().value() ^ System.getTimer());
        var text = "";
        for (var i = 0; i < 4; i++) {
            // 8 hex digits per part (31 random bits each).
            text += Math.rand().format("%08x");
        }
        Application.Storage.setValue("share_uid", text);
    }

    // Sharing switched on: Kennung, and queue all own bins not shared yet.
    function onConsent() as Void {
        ensureUid();
        enqueueUnshared();
    }

    // Sharing switched off: forget the Kennung and everything not sent yet.
    function forget() as Void {
        Application.Storage.deleteValue("share_uid");
        items = [] as Array<Array>;
        persist();
    }

    // --- adding Beiträge -------------------------------------------------------------

    function push(item as Array) as Void {
        if (!Consent.given() || items.size() >= MAX_ITEMS) {
            return;
        }
        items.add(item);
        persist();
    }

    function addBin(ref as Number, kind as Number, lat as Float, lon as Float, imprecise as Boolean) as Void {
        push(["a", kind, lat, lon, imprecise ? 1 : 0, 0, ref]);
    }

    // Own bins without Server-Kennung and without a queued "a" (bins from
    // before Etappe B, or added without consent).
    function enqueueUnshared() as Void {
        if (!Consent.given()) {
            return;
        }
        ensureUid();
        for (var i = 0; i < Bins.ownRef.size(); i++) {
            if (Bins.ownSid[i] == 0 && queuedAdd(Bins.ownRef[i]) == null) {
                addBin(Bins.ownRef[i], Bins.ownKind[i], Bins.ownLat[i], Bins.ownLon[i], false);
            }
        }
    }

    function queuedAdd(ref as Number) as Array? {
        for (var i = 0; i < items.size(); i++) {
            if ("a".equals(items[i][F_TYPE]) && items[i][F_REF] == ref) {
                return items[i];
            }
        }
        return null;
    }

    function report(bin as Bin, sid as Number) as Void {
        push(["r", bin.kind, bin.lat, bin.lon, 0, sid, 0]);
    }

    function confirm(sid as Number) as Void {
        push(["f", 0, 0.0, 0.0, 0, sid, 0]);
    }

    // An own bin was deleted on the watch (call before Bins.remove).
    function ownRemoved(bin as Bin) as Void {
        var i = bin.src;
        var sid = Bins.ownSid[i];
        if (sid == 0) {
            var queued = queuedAdd(Bins.ownRef[i]);
            if (queued != null && sending.indexOf(queued) < 0) {
                items.remove(queued);
                persist();
            }
            // If it is being sent right now, onResponse handles it.
            return;
        }
        if (Bins.ownConf[i] == 1) {
            push(["r", bin.kind, bin.lat, bin.lon, 0, sid, 0]);
        } else {
            push(["x", 0, 0.0, 0.0, 0, sid, 0]);
        }
    }

    // --- sending ------------------------------------------------------------------

    // Sends the next batch if possible. True if a request was started.
    function flush(canRequest as Boolean) as Boolean {
        if (busy || items.size() == 0 || !canRequest || Time.now().value() < retryAt) {
            return false;
        }
        var u = uid();
        if (u == null) {
            return false;
        }
        var n = items.size() < BATCH ? items.size() : BATCH;
        sending = items.slice(0, n);
        var events = [] as Array<Dictionary>;
        for (var i = 0; i < n; i++) {
            events.add(event(sending[i]));
        }
        busy = true;
        Communications.makeWebRequest(ServerConfig.BASE + PATH, {"u" => u, "e" => events}, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "User-Agent" => OsmLoader.USER_AGENT
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, new Lang.Method(ShareQueue, :onResponse));
        return true;
    }

    function event(item as Array) as Dictionary {
        var t = item[F_TYPE] as String;
        if ("a".equals(t)) {
            return {"t" => t, "k" => kindCode(item[F_KIND] as Number), "la" => item[F_LAT], "lo" => item[F_LON],
                "i" => item[F_IMP]};
        }
        if ("r".equals(t)) {
            return {"t" => t, "k" => kindCode(item[F_KIND] as Number), "la" => item[F_LAT], "lo" => item[F_LON],
                "s" => item[F_SID]};
        }
        return {"t" => t, "s" => item[F_SID]};
    }

    function kindCode(kind as Number) as String {
        return kind == Bins.KIND_DOG ? "d" : "g";
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        busy = false;
        lastCode = code;
        var sent = sending;
        sending = [] as Array<Array>;
        var now = Time.now().value();
        if (code == 400) {
            // The server cannot read this batch: drop it, never block the queue.
            removeAll(sent);
            return;
        }
        if (code != 200 || !(data instanceof Dictionary) || !(data["r"] instanceof Array)) {
            System.println("share: failed " + code.toString());
            retryAt = now + RETRY_ERROR_S;
            return;
        }
        var results = data["r"] as Array;
        var done = [] as Array<Array>;
        for (var i = 0; i < sent.size(); i++) {
            var item = sent[i];
            var r = i < results.size() ? results[i] : null;
            if (!(r instanceof Dictionary)) {
                continue;
            }
            var err = r["err"];
            if (err != null) {
                if ("bad".equals(err)) {
                    done.add(item);
                } else {
                    retryAt = now + RETRY_LIMIT_S;
                }
                continue;
            }
            done.add(item);
            var sid = number(r["s"]);
            if ("a".equals(item[F_TYPE]) && sid != null && sid > 0) {
                var f = number(r["f"]);
                added(item, sid, f != null && f == 1);
            }
        }
        removeAll(done);
        System.println("share: sent " + done.size().toString() + ", waiting " + items.size().toString());
    }

    // JSON numbers arrive as Number in the simulator, but through the phone
    // app possibly as Long, Float or Double.
    function number(v) as Number? {
        if (v instanceof Number) {
            return v;
        }
        if (v instanceof Long || v instanceof Float || v instanceof Double) {
            return v.toNumber();
        }
        if (v instanceof String) {
            return v.toNumber();
        }
        return null;
    }

    // The server stored (or confirmed) an added bin.
    function added(item as Array, sid as Number, confirmed as Boolean) as Void {
        var ref = item[F_REF] as Number;
        if (Bins.ownIndex(ref) >= 0) {
            Bins.setOwnSid(ref, sid, confirmed);
        } else {
            // Deleted on the watch while it was being sent.
            if (confirmed) {
                items.add(["r", item[F_KIND], item[F_LAT], item[F_LON], 0, sid, 0]);
            } else {
                items.add(["x", 0, 0.0, 0.0, 0, sid, 0]);
            }
        }
    }

    function removeAll(list as Array<Array>) as Void {
        for (var i = 0; i < list.size(); i++) {
            items.remove(list[i]);
        }
        persist();
    }
}
