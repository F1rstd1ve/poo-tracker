import Toybox.Lang;
import Toybox.WatchUi;

// What the LAP button does during a Spaziergang (ADR 0005, extended
// 18.11.2026), the most likely action first:
//   Rückweg-Alarm ausgelöst (≥ 50 m weg, wieder ≤ 25 m dran)  -> Aufgehoben
//   Sack in der Hand, bekannter Mülleimer ≤ 15 m             -> Entsorgt
//   Sack in der Hand, kein Mülleimer bekannt                 -> Auswahl:
//       Entsorgt – Mülleimer hier / Hundekot-Behälter hier / Neuen Sack ablegen
//   sonst                                                     -> Sack ablegen
// Staying near a bag just dropped never picks it up again (the alarm only
// triggers after walking away), so a second drop right there still works.
module LapAction {

    function run() as Void {
        if (ReturnAlarm.isActive()) {
            pickUp();
        } else if (DepotStore.countIn(DepotStore.STATE_PICKED) > 0) {
            dispose(true);
        } else {
            DropBag.start();
        }
    }

    function pickUp() as Void {
        ReturnAlarm.pickUp();
        Pages.map().refreshDepots();
        WalkSession.updateFit();
        Feedback.vibe();
        Feedback.toast(Rez.Strings.PickedUp);
        Pages.showBins();
    }

    // "Entsorgt": directly at a known bin; otherwise ask what is here.
    // fromLap: the third choice is "Neuen Sack ablegen"; from the Aktionsmenü
    // it is "kein öffentlicher Mülleimer" (e.g. the bin at home - never shared).
    function dispose(fromLap as Boolean) as Void {
        var here = GpsService.position();
        if (here == null) {
            Disposal.dispose(false);
            return;
        }
        var p = Bins.degrees(here);
        Bins.onPosition(here);
        var d = Bins.nearestDistance(p[0], p[1]);
        if (d >= 0 && d <= Disposal.RADIUS_M) {
            Disposal.dispose(false);
            return;
        }
        var menu = new WatchUi.Menu2({:title => Rez.Strings.DisposeHereTitle});
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.DisposeBinHere, null, :general, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.DisposeDogBinHere, null, :dog, null));
        if (fromLap) {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.DropNewBag, null, :drop, null));
        } else {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.DisposeNoPublic, Rez.Strings.DisposeNoPublicSub,
                :private, null));
        }
        WatchUi.pushView(menu, new DisposeHereDelegate(), WatchUi.SLIDE_UP);
    }
}

class DisposeHereDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :drop) {
            DropBag.start();
            return;
        }
        Disposal.dispose(false);
        if (id == :general) {
            BinActions.startAdd(Bins.KIND_GENERAL);
        } else if (id == :dog) {
            BinActions.startAdd(Bins.KIND_DOG);
        }
    }
}
