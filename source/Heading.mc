import Toybox.Lang;
import Toybox.Sensor;

// Direction the wearer is facing, in radians (0 = north, clockwise).
// Spec: compass first (works while standing still), GPS course as fallback.
module Heading {

    function current() as Float {
        var sensor = Sensor.getInfo();
        if (sensor has :heading && sensor.heading != null) {
            return sensor.heading as Float;
        }
        var info = GpsService.lastInfo;
        if (info != null && info.heading != null) {
            return info.heading as Float;
        }
        return 0.0;
    }
}
