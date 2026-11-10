import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.WatchUi;

// The recorded Spaziergang: a FIT activity with sport "walking" that syncs to
// Garmin Connect like the native Walk app (ADR 0001).
//
// Note on ActivityRecording: session.stop() only pauses the timer;
// save()/discard() end the session.
module WalkSession {

    var session as ActivityRecording.Session? = null;

    // FIT developer fields: open bags over time (graph) and bags dropped (summary).
    var openBagsField as FitContributor.Field? = null;
    var droppedField as FitContributor.Field? = null;
    var droppedCount as Number = 0;

    function start() as Void {
        if (session != null) {
            return;
        }
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        var s = ActivityRecording.createSession({
            :name => WatchUi.loadResource(Rez.Strings.AppName) as String,
            :sport => Activity.SPORT_WALKING,
            :subSport => Activity.SUB_SPORT_GENERIC
        });
        openBagsField = s.createField("open_bags", 0, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "bags"});
        droppedField = s.createField("bags_dropped", 1, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bags"});
        droppedCount = 0;
        Fields.rememberSteps();
        s.start();
        session = s;
        updateFit();
    }

    function onBagDropped() as Void {
        droppedCount++;
        updateFit();
    }

    function onBagUndone() as Void {
        if (droppedCount > 0) {
            droppedCount--;
        }
        updateFit();
    }

    function updateFit() as Void {
        var open = openBagsField;
        if (open != null) {
            open.setData(DepotStore.countIn(DepotStore.STATE_OPEN));
        }
        var dropped = droppedField;
        if (dropped != null) {
            dropped.setData(droppedCount);
        }
    }

    function hasStarted() as Boolean {
        return session != null;
    }

    function isRecording() as Boolean {
        var s = session;
        return s != null && s.isRecording();
    }

    function isPaused() as Boolean {
        var s = session;
        return s != null && !s.isRecording();
    }

    function pause() as Void {
        var s = session;
        if (s != null && s.isRecording()) {
            s.stop();
        }
    }

    function resume() as Void {
        var s = session;
        if (s != null && !s.isRecording()) {
            s.start();
        }
    }

    function save() as Boolean {
        var s = session;
        if (s == null) {
            return false;
        }
        if (s.isRecording()) {
            s.stop();
        }
        var ok = s.save();
        session = null;
        openBagsField = null;
        droppedField = null;
        return ok;
    }

    function discard() as Void {
        var s = session;
        if (s == null) {
            return;
        }
        if (s.isRecording()) {
            s.stop();
        }
        s.discard();
        session = null;
        openBagsField = null;
        droppedField = null;
    }
}
