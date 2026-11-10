import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

// Great-circle helpers. All distances in meters, bearings in radians
// (0 = north, clockwise).
module GeoUtil {

    const EARTH_RADIUS_M = 6371000.0d;

    function distance(a as Position.Location, b as Position.Location) as Float {
        var ra = a.toRadians();
        var rb = b.toRadians();
        var dLat = rb[0] - ra[0];
        var dLon = rb[1] - ra[1];
        var sinLat = Math.sin(dLat / 2);
        var sinLon = Math.sin(dLon / 2);
        var h = sinLat * sinLat + Math.cos(ra[0]) * Math.cos(rb[0]) * sinLon * sinLon;
        if (h > 1.0d) {
            h = 1.0d;
        }
        return (2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h))).toFloat();
    }

    function bearing(from as Position.Location, to as Position.Location) as Float {
        var ra = from.toRadians();
        var rb = to.toRadians();
        var dLon = rb[1] - ra[1];
        var y = Math.sin(dLon) * Math.cos(rb[0]);
        var x = Math.cos(ra[0]) * Math.sin(rb[0]) - Math.sin(ra[0]) * Math.cos(rb[0]) * Math.cos(dLon);
        return Math.atan2(y, x).toFloat();
    }

    // Location reached by travelling `meters` from `origin` towards `heading`.
    function project(origin as Position.Location, heading as Float, meters as Float) as Position.Location {
        var r = origin.toRadians();
        var d = meters / EARTH_RADIUS_M;
        var lat2 = Math.asin(Math.sin(r[0]) * Math.cos(d) + Math.cos(r[0]) * Math.sin(d) * Math.cos(heading));
        var lon2 = r[1] + Math.atan2(
            Math.sin(heading) * Math.sin(d) * Math.cos(r[0]),
            Math.cos(d) - Math.sin(r[0]) * Math.sin(lat2));
        return new Position.Location({
            :latitude => lat2,
            :longitude => lon2,
            :format => :radians
        });
    }
}
