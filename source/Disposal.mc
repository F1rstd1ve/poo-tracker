import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;

// "Entsorgt": by hand from the Aktionsmenü, or automatically when standing
// (almost) still for >= 3 s within 15 m of a bin while carrying a bag.
// An automatic disposal can be undone for 30 s.
module Disposal {

    const RADIUS_M = 15.0;
    const STILL_SPEED_MPS = 0.6;
    const STILL_SECONDS = 3;
    const UNDO_SECONDS = 30;

    var stillSince as Number? = null;
    var undoDepots as Array<Dictionary>? = null;
    var undoUntil as Number = 0;

    function update(info as Position.Info, here as Position.Location) as Void {
        if (DepotStore.countIn(DepotStore.STATE_PICKED) == 0) {
            stillSince = null;
            return;
        }
        var p = Bins.degrees(here);
        var d = Bins.nearestDistance(p[0], p[1]);
        var speed = info.speed;
        if (d < 0 || d > RADIUS_M || (speed != null && speed > STILL_SPEED_MPS)) {
            stillSince = null;
            return;
        }
        var now = Time.now().value();
        var since = stillSince;
        if (since == null) {
            stillSince = now;
        } else if (now - since >= STILL_SECONDS) {
            dispose(true);
        }
    }

    function dispose(automatic as Boolean) as Void {
        undoDepots = DepotStore.inState(DepotStore.STATE_PICKED);
        undoUntil = automatic ? Time.now().value() + UNDO_SECONDS : 0;
        DepotStore.removeInState(DepotStore.STATE_PICKED);
        stillSince = null;
        Pages.returnFromBins();
        Feedback.vibe();
        Feedback.toast(automatic ? Rez.Strings.DisposedAuto : Rez.Strings.Disposed);
    }

    function canUndo() as Boolean {
        return undoDepots != null && Time.now().value() < undoUntil;
    }

    function undo() as Void {
        var list = undoDepots;
        if (list == null) {
            return;
        }
        for (var i = 0; i < list.size(); i++) {
            list[i]["s"] = DepotStore.STATE_PICKED;
            DepotStore.depots.add(list[i]);
        }
        DepotStore.persist();
        undoDepots = null;
        undoUntil = 0;
        Pages.showBins();
        Feedback.toast(Rez.Strings.Undone);
    }
}
