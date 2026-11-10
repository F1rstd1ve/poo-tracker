import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Runs `action(imprecise)` with a usable GPS fix. Spec: with a usable fix at
// once; otherwise "Warte auf GPS…" for at most 30 s, then with the best
// available (poor) fix flagged as imprecise, or give up without any fix.
// A merely "last known" position is never used (could be somewhere else).
module GpsWait {

    const WAIT_SECONDS = 30;

    function run(action as Method(imprecise as Boolean) as Void) as Void {
        if (GpsService.quality() >= Position.QUALITY_USABLE) {
            action.invoke(false);
        } else {
            WatchUi.pushView(new WaitGpsView(action), new WaitGpsDelegate(), WatchUi.SLIDE_IMMEDIATE);
        }
    }
}

// "Sack ablegen": store the current position as a Sackdepot (imprecise ones
// get the 40 m trigger radius). Because a single LAP press drops a bag
// (ADR 0005), the last drop can be undone from the Aktionsmenü for 30 s.
module DropBag {

    const UNDO_SECONDS = 30;

    var lastId as Number? = null;
    var undoUntil as Number = 0;

    function start() as Void {
        GpsWait.run(new Lang.Method(DropBag, :commit));
    }

    function commit(imprecise as Boolean) as Void {
        var here = GpsService.position();
        if (here == null) {
            Feedback.toast(Rez.Strings.NoGpsNotSaved);
            return;
        }
        var depot = DepotStore.add(here, imprecise);
        lastId = DepotStore.id(depot);
        undoUntil = Time.now().value() + UNDO_SECONDS;
        WalkSession.onBagDropped();
        Pages.map().refreshDepots();
        Feedback.vibe();
        Feedback.toast(imprecise ? Rez.Strings.DepotSavedImprecise : Rez.Strings.DepotSaved);
    }

    function canUndo() as Boolean {
        return lastId != null && Time.now().value() < undoUntil;
    }

    function undo() as Void {
        var depotId = lastId;
        lastId = null;
        undoUntil = 0;
        if (depotId == null) {
            return;
        }
        ReturnAlarm.forget(depotId);
        DepotStore.removeById(depotId);
        WalkSession.onBagUndone();
        Pages.map().refreshDepots();
        Feedback.toast(Rez.Strings.Undone);
    }
}

class WaitGpsView extends WatchUi.View {

    private var _timer as Timer.Timer?;
    private var _elapsed as Number = 0;
    private var _action as Method(imprecise as Boolean) as Void;

    function initialize(action as Method(imprecise as Boolean) as Void) {
        View.initialize();
        _action = action;
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:tick), 1000, true);
        _timer = t;
    }

    function onHide() as Void {
        stopTimer();
    }

    private function stopTimer() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
    }

    function tick() as Void {
        _elapsed++;
        var quality = GpsService.quality();
        if (quality >= Position.QUALITY_USABLE) {
            finish(false);
        } else if (_elapsed >= GpsWait.WAIT_SECONDS) {
            if (quality >= Position.QUALITY_POOR) {
                finish(true);
            } else {
                stopTimer();
                WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
                Feedback.toast(Rez.Strings.NoGpsNotSaved);
            }
        } else {
            WatchUi.requestUpdate();
        }
    }

    private function finish(imprecise as Boolean) as Void {
        stopTimer();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        _action.invoke(imprecise);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.42, Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.WaitingForGps) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.6, Graphics.FONT_NUMBER_MILD,
            (GpsWait.WAIT_SECONDS - _elapsed).toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// BACK cancels the drop.
class WaitGpsDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        Feedback.toast(Rez.Strings.Cancelled);
        return true;
    }
}
