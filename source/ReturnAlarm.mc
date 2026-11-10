import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

// Rückweg-Alarm. Per open Sackdepot:
//   not armed --(distance >= ARM)--> scharf --(distance <= TRIGGER)--> ausgelöst
//   ausgelöst --(distance > ARM, unconfirmed)--> scharf again
// Several depots in range share one alarm. An alarm vibrates + beeps + shows the
// alarm screen; it repeats every 30 s, at most 3 times, until "Aufgehoben".
// Runtime state only: after an app restart every depot starts "not armed".
module ReturnAlarm {

    const REPEAT_MS = 30000;
    const MAX_ALERTS = 3;

    var armed as Dictionary<Number, Boolean> = {} as Dictionary<Number, Boolean>;
    var triggered as Dictionary<Number, Boolean> = {} as Dictionary<Number, Boolean>;
    var alertsFired as Number = 0;
    var repeatTimer as Timer.Timer? = null;
    var viewShown as Boolean = false;

    function update(here as Position.Location) as Void {
        var newlyTriggered = false;
        var open = DepotStore.inState(DepotStore.STATE_OPEN);
        for (var i = 0; i < open.size(); i++) {
            var depot = open[i];
            var id = DepotStore.id(depot);
            var dist = GeoUtil.distance(here, DepotStore.location(depot));
            if (triggered.hasKey(id)) {
                if (dist > Settings.armRadius) {
                    triggered.remove(id);
                    armed.put(id, true);
                }
            } else if (armed.hasKey(id)) {
                var radius = DepotStore.isImprecise(depot) ? Settings.triggerRadiusImprecise() : Settings.triggerRadius;
                if (dist <= radius) {
                    armed.remove(id);
                    triggered.put(id, true);
                    newlyTriggered = true;
                }
            } else if (dist >= Settings.armRadius) {
                armed.put(id, true);
            }
        }

        if (newlyTriggered) {
            alertsFired = 0;
            fire();
            startRepeat();
        } else if (triggeredDepots().size() == 0) {
            stopRepeat();
            hideView();
        } else if (viewShown) {
            WatchUi.requestUpdate();
        }
    }

    // Open depots whose alarm is currently ausgelöst.
    function triggeredDepots() as Array<Dictionary> {
        var result = [] as Array<Dictionary>;
        var open = DepotStore.inState(DepotStore.STATE_OPEN);
        for (var i = 0; i < open.size(); i++) {
            if (triggered.hasKey(DepotStore.id(open[i]))) {
                result.add(open[i]);
            }
        }
        return result;
    }

    function isActive() as Boolean {
        return triggeredDepots().size() > 0;
    }

    // "Aufgehoben": every ausgelöst depot becomes aufgehoben.
    function pickUp() as Void {
        var list = triggeredDepots();
        var ids = [] as Array<Number>;
        for (var i = 0; i < list.size(); i++) {
            ids.add(DepotStore.id(list[i]));
        }
        DepotStore.setState(ids, DepotStore.STATE_PICKED);
        triggered = {} as Dictionary<Number, Boolean>;
        stopRepeat();
        hideView();
    }

    // A depot was deleted by hand.
    function forget(depotId as Number) as Void {
        armed.remove(depotId);
        triggered.remove(depotId);
        if (!isActive()) {
            stopRepeat();
            hideView();
        }
    }

    function fire() as Void {
        alertsFired++;
        Feedback.alarm();
        showView();
    }

    function startRepeat() as Void {
        stopRepeat();
        var t = new Timer.Timer();
        t.start(new Lang.Method(ReturnAlarm, :onRepeat), REPEAT_MS, true);
        repeatTimer = t;
    }

    function onRepeat() as Void {
        if (!isActive() || alertsFired >= MAX_ALERTS) {
            stopRepeat();
            return;
        }
        fire();
    }

    function stopRepeat() as Void {
        var t = repeatTimer;
        if (t != null) {
            t.stop();
        }
        repeatTimer = null;
    }

    function showView() as Void {
        if (viewShown) {
            WatchUi.requestUpdate();
            return;
        }
        viewShown = true;
        WatchUi.pushView(new AlarmView(), new AlarmDelegate(), WatchUi.SLIDE_UP);
    }

    function hideView() as Void {
        if (viewShown) {
            viewShown = false;
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    // The user left the alarm screen with UP/DOWN; the alarm itself stays active.
    function viewDismissed() as Void {
        viewShown = false;
    }
}
