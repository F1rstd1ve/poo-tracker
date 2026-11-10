import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.WatchUi;

// The 14 selectable values of a Datenseite (spec, ADR 0003).
// Values contain only digits, ":", "." and "-" so they render in the number
// fonts; units go into the label.
module Fields {

    const TIMER = 0;
    const DISTANCE = 1;
    const PACE = 2;
    const AVG_PACE = 3;
    const HEART_RATE = 4;
    const AVG_HEART_RATE = 5;
    const ELEVATION = 6;
    const ASCENT = 7;
    const CALORIES = 8;
    const STEPS = 9;
    const CLOCK = 10;
    const OPEN_BAGS = 11;
    const DIST_BAG = 12;
    const DIST_BIN = 13;
    const COUNT = 14;

    const NONE = "--";

    var stepsAtStart as Number? = null;

    function label(field as Number) as String {
        var labels = [
            Rez.Strings.Lbl0, Rez.Strings.Lbl1, Rez.Strings.Lbl2, Rez.Strings.Lbl3, Rez.Strings.Lbl4,
            Rez.Strings.Lbl5, Rez.Strings.Lbl6, Rez.Strings.Lbl7, Rez.Strings.Lbl8, Rez.Strings.Lbl9,
            Rez.Strings.Lbl10, Rez.Strings.Lbl11, Rez.Strings.Lbl12, Rez.Strings.Lbl13
        ];
        var text = WatchUi.loadResource(labels[field]) as String;
        var unit = unitOf(field);
        return unit.length() > 0 ? text + " " + unit : text;
    }

    function unitOf(field as Number) as String {
        var metric = Format.isMetric();
        if (field == DISTANCE) {
            return metric ? "km" : "mi";
        }
        if (field == PACE || field == AVG_PACE) {
            return metric ? "/km" : "/mi";
        }
        if (field == ELEVATION || field == ASCENT || field == DIST_BAG || field == DIST_BIN) {
            return metric ? "m" : "ft";
        }
        return "";
    }

    function rememberSteps() as Void {
        stepsAtStart = currentSteps();
    }

    function currentSteps() as Number? {
        var info = ActivityMonitor.getInfo();
        return info != null ? info.steps : null;
    }

    function value(field as Number) as String {
        var info = Activity.getActivityInfo();
        if (field == CLOCK) {
            return Format.clock();
        }
        if (field == OPEN_BAGS) {
            return DepotStore.countIn(DepotStore.STATE_OPEN).toString();
        }
        if (field == DIST_BAG) {
            return distBag();
        }
        if (field == DIST_BIN) {
            return distBin();
        }
        if (field == STEPS) {
            var now = currentSteps();
            var start = stepsAtStart;
            if (now == null) {
                return NONE;
            }
            if (start == null || now < start) {
                return now.toString();
            }
            return (now - start).toString();
        }
        if (field == TIMER) {
            return info.timerTime != null ? Format.duration(info.timerTime as Number) : "0:00";
        }
        if (field == DISTANCE) {
            return info.elapsedDistance != null ? Format.distance(info.elapsedDistance as Float) : Format.distance(0.0);
        }
        if (field == PACE) {
            return Format.pace(info.currentSpeed);
        }
        if (field == AVG_PACE) {
            return Format.pace(info.averageSpeed);
        }
        if (field == HEART_RATE) {
            return numberOr(info.currentHeartRate);
        }
        if (field == AVG_HEART_RATE) {
            return numberOr(info.averageHeartRate);
        }
        if (field == ELEVATION) {
            return info.altitude != null ? Format.length(info.altitude as Float) : NONE;
        }
        if (field == ASCENT) {
            return info.totalAscent != null ? Format.length((info.totalAscent as Number).toFloat()) : NONE;
        }
        if (field == CALORIES) {
            return numberOr(info.calories);
        }
        return NONE;
    }

    function numberOr(v as Number?) as String {
        return v != null ? v.toString() : NONE;
    }

    function distBag() as String {
        var here = GpsService.position();
        if (here == null) {
            return NONE;
        }
        var depot = DepotStore.nearest(here, DepotStore.STATE_OPEN);
        if (depot == null) {
            return NONE;
        }
        return Format.length(GeoUtil.distance(here, DepotStore.location(depot)));
    }

    function distBin() as String {
        var here = GpsService.position();
        if (here == null) {
            return NONE;
        }
        var p = Bins.degrees(here);
        var bin = Bins.target(p[0], p[1]);
        if (bin == null) {
            return NONE;
        }
        return Format.length(Bins.dist(p[0], p[1], bin.lat, bin.lon));
    }
}
