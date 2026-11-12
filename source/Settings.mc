import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// App settings, edited in the Connect IQ phone app (ADR 0003).
// Values are validated so a broken setting can never crash the watch.
module Settings {

    var pageOn as Array<Boolean> = [true, true, false] as Array<Boolean>;
    var pageLayout as Array<Number> = [4, 3, 2] as Array<Number>;
    var pageFields as Array<Array<Number>> = [
        [0, 1, 4, 10], [11, 12, 13, 1], [2, 3, 4, 5]
    ] as Array<Array<Number>>;
    var binsPage as Boolean = true;
    var mapPage as Boolean = true;
    var armRadius as Float = 50.0;
    var triggerRadius as Float = 25.0;
    var alarmTone as Boolean = true;
    var osm as Boolean = true;
    // Touchscreen while the app runs (like the Garmin activity option "Touch").
    var touch as Boolean = true;
    var gpsMode as Number = 0;

    function load() as Void {
        for (var p = 0; p < 3; p++) {
            var prefix = "p" + (p + 1).toString();
            pageOn[p] = bool(prefix + "On", pageOn[p]);
            pageLayout[p] = clamp(num(prefix + "Lay", pageLayout[p]), 1, 4);
            for (var f = 0; f < 4; f++) {
                pageFields[p][f] = clamp(num(prefix + "F" + (f + 1).toString(), pageFields[p][f]), 0, Fields.COUNT - 1);
            }
        }
        binsPage = bool("binsOn", binsPage);
        mapPage = bool("mapOn", mapPage);
        triggerRadius = clamp(num("trigR", 25), 10, 100).toFloat();
        armRadius = clamp(num("armR", 50), 30, 300).toFloat();
        if (armRadius < triggerRadius + 15) {
            armRadius = triggerRadius + 15;
        }
        alarmTone = bool("tone", alarmTone);
        osm = bool("osm", osm);
        touch = bool("touch", touch);
        gpsMode = clamp(num("gps", gpsMode), 0, 2);
    }

    // Turns the touchscreen on/off while the app is in the foreground
    // (API 5.2.0; older devices keep touch, the app still ignores taps that
    // could start, pause or drop something, ADR 0007).
    function applyTouch() as Void {
        if (WatchUi has :configureTouchEvents) {
            try {
                WatchUi.configureTouchEvents({:enabled => touch});
            } catch (e) {
            }
        }
    }

    // Changed on the watch (start screen menu).
    function setTouch(on as Boolean) as Void {
        touch = on;
        try {
            Application.Properties.setValue("touch", on);
        } catch (e) {
        }
        applyTouch();
    }

    // Spec: 40 m for imprecise depots, never less than the normal radius + 15 m.
    function triggerRadiusImprecise() as Float {
        return triggerRadius + 15 > 40.0 ? triggerRadius + 15 : 40.0;
    }

    function num(key as String, fallback as Number) as Number {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Number) {
                return v;
            }
            if (v instanceof Float || v instanceof Double || v instanceof Long) {
                return v.toNumber();
            }
        } catch (e) {
        }
        return fallback;
    }

    function bool(key as String, fallback as Boolean) as Boolean {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Boolean) {
                return v;
            }
        } catch (e) {
        }
        return fallback;
    }

    function clamp(v as Number, lo as Number, hi as Number) as Number {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}
