import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Display formatting. Units follow the watch's system settings.
module Format {

    const METERS_PER_MILE = 1609.344;

    // Milliseconds -> "M:SS" or "H:MM:SS".
    function duration(ms as Number) as String {
        var total = ms / 1000;
        var hours = total / 3600;
        var minutes = (total % 3600) / 60;
        var seconds = total % 60;
        if (hours > 0) {
            return hours.format("%d") + ":" + minutes.format("%02d") + ":" + seconds.format("%02d");
        }
        return minutes.format("%d") + ":" + seconds.format("%02d");
    }

    function isMetric() as Boolean {
        return System.getDeviceSettings().distanceUnits != System.UNIT_STATUTE;
    }

    // Meters -> "1.23" (km or mi, depending on settings).
    function distance(meters as Float) as String {
        var value = isMetric() ? meters / 1000.0 : meters / METERS_PER_MILE;
        return value.format("%.2f");
    }

    function distanceLabel() as ResourceId {
        return isMetric() ? Rez.Strings.LabelDistanceKm : Rez.Strings.LabelDistanceMi;
    }

    // Meters -> whole meters or feet, number only (unit is in the label).
    function length(meters as Float) as String {
        var v = isMetric() ? meters : meters * 3.28084;
        return v.format("%d");
    }

    // Speed (m/s) -> pace "M:SS" per km or mile; "--:--" when (almost) standing.
    function pace(speed as Float?) as String {
        if (speed == null || speed < 0.3) {
            return "--:--";
        }
        var perUnit = isMetric() ? 1000.0 : METERS_PER_MILE;
        var seconds = (perUnit / speed).toNumber();
        if (seconds >= 6000) {
            return "--:--";
        }
        return (seconds / 60).format("%d") + ":" + (seconds % 60).format("%02d");
    }

    // Short distances for guidance: "18 m" / "1.2 km" (metric), "60 ft" / "0.3 mi".
    function shortDistance(meters as Float) as String {
        if (isMetric()) {
            if (meters < 1000) {
                return meters.format("%d") + " m";
            }
            return (meters / 1000.0).format("%.1f") + " km";
        }
        var feet = meters * 3.28084;
        if (feet < 1000) {
            return feet.format("%d") + " ft";
        }
        return (meters / METERS_PER_MILE).format("%.1f") + " mi";
    }

    // Seconds -> "vor 5 min" / "vor 3 Std." / "vor 2 Tagen".
    function age(seconds as Number) as String {
        var minutes = seconds / 60;
        if (minutes < 60) {
            return Lang.format(WatchUi.loadResource(Rez.Strings.AgeMin) as String, [minutes]);
        }
        var hours = minutes / 60;
        if (hours < 48) {
            return Lang.format(WatchUi.loadResource(Rez.Strings.AgeHours) as String, [hours]);
        }
        return Lang.format(WatchUi.loadResource(Rez.Strings.AgeDays) as String, [hours / 24]);
    }

    // "1 Sack" / "3 Säcke"
    function bags(count as Number) as String {
        if (count == 1) {
            return WatchUi.loadResource(Rez.Strings.BagsOne) as String;
        }
        return Lang.format(WatchUi.loadResource(Rez.Strings.BagsMany) as String, [count]);
    }

    // Time of day, 24h or 12h according to settings.
    function clock() as String {
        var t = System.getClockTime();
        var hour = t.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour.format("%d") + ":" + t.min.format("%02d");
    }
}
