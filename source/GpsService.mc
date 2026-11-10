import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;

// Starts and stops continuous positioning. Spec: default is
// "all systems + multi-band", with fallback to whatever the device supports.
module GpsService {

    var lastInfo as Position.Info? = null;

    function start(callback as Method(info as Position.Info) as Void) as Void {
        var config = bestConfiguration();
        if (config != null) {
            Position.enableLocationEvents({
                :acquisitionType => Position.LOCATION_CONTINUOUS,
                :configuration => config
            }, callback);
        } else {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, callback);
        }
    }

    function stop() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
    }

    // Position.QUALITY_* of the last fix (NOT_AVAILABLE without a position).
    function quality() as Number {
        var info = lastInfo;
        if (info == null || info.position == null) {
            return Position.QUALITY_NOT_AVAILABLE;
        }
        return info.accuracy as Number;
    }

    function position() as Position.Location? {
        var info = lastInfo;
        return info != null ? info.position : null;
    }

    function hasUsableFix() as Boolean {
        var info = lastInfo;
        return info != null && info.position != null && info.accuracy >= Position.QUALITY_POOR;
    }

    // Green = good, yellow = usable/poor, red = no fix.
    function statusColor() as Graphics.ColorType {
        var info = lastInfo;
        if (info == null || info.position == null || info.accuracy < Position.QUALITY_POOR) {
            return Graphics.COLOR_RED;
        }
        if (info.accuracy >= Position.QUALITY_GOOD) {
            return Graphics.COLOR_GREEN;
        }
        return Graphics.COLOR_YELLOW;
    }

    function bestConfiguration() as Position.Configuration? {
        if (!(Position has :hasConfigurationSupport)) {
            return null;
        }
        // Settings.gpsMode: 0 = all systems + multi-band, 1 = all systems, 2 = GPS only
        if (Settings.gpsMode == 2) {
            if (Position has :CONFIGURATION_GPS && Position.hasConfigurationSupport(Position.CONFIGURATION_GPS)) {
                return Position.CONFIGURATION_GPS;
            }
            return null;
        }
        if (Settings.gpsMode == 0 && Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5
                && Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5)) {
            return Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5;
        }
        if (Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1
                && Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1)) {
            return Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1;
        }
        return null;
    }
}
