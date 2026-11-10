import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

// "Mülleimer hinzufügen" / "Mülleimer entfernen" from the Aktionsmenü.
module BinActions {

    const DUPLICATE_RADIUS_M = 10.0;
    const REMOVE_RADIUS_M = 100.0;

    var pendingLocation as Position.Location? = null;
    var candidates as Array<Bin> = [] as Array<Bin>;

    function startAdd() as Void {
        GpsWait.run(new Lang.Method(BinActions, :commitAdd));
    }

    function commitAdd(imprecise as Boolean) as Void {
        var here = GpsService.position();
        if (here == null) {
            Feedback.toast(Rez.Strings.NoGpsNotSaved);
            return;
        }
        var p = Bins.degrees(here);
        Bins.onPosition(here);
        if (Bins.hasBinWithin(p[0], p[1], DUPLICATE_RADIUS_M)) {
            // Spec: ask, with "No" preselected (first entry).
            pendingLocation = here;
            var menu = new WatchUi.Menu2({:title => Rez.Strings.BinExists});
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.Cancel, null, :cancel, null));
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.SaveAnyway, null, :save, null));
            WatchUi.pushView(menu, new DuplicateBinDelegate(), WatchUi.SLIDE_UP);
            return;
        }
        save(here);
    }

    function save(loc as Position.Location) as Void {
        Bins.addOwn(loc);
        Feedback.vibe();
        Feedback.toast(Rez.Strings.BinSaved);
    }

    // The three nearest bins within 100 m.
    function openRemoveMenu() as Void {
        var here = GpsService.position();
        if (here == null) {
            Feedback.toast(Rez.Strings.NoGps);
            return;
        }
        var p = Bins.degrees(here);
        Bins.onPosition(here);
        candidates = Bins.nearestN(p[0], p[1], 3, REMOVE_RADIUS_M);
        if (candidates.size() == 0) {
            Feedback.toast(Rez.Strings.NoBinNearby);
            return;
        }
        var menu = new WatchUi.Menu2({:title => Rez.Strings.RemoveBin});
        for (var i = 0; i < candidates.size(); i++) {
            var b = candidates[i];
            menu.addItem(new WatchUi.MenuItem(
                Format.shortDistance(Bins.dist(p[0], p[1], b.lat, b.lon)),
                WatchUi.loadResource(kindLabel(b.kind)) as String,
                i, null));
        }
        WatchUi.pushView(menu, new RemoveBinDelegate(), WatchUi.SLIDE_LEFT);
    }

    function kindLabel(kind as Number) as ResourceId {
        if (kind == Bins.KIND_OWN) {
            return Rez.Strings.KindOwn;
        }
        if (kind == Bins.KIND_OSM_DOG) {
            return Rez.Strings.KindDog;
        }
        return Rez.Strings.KindOsm;
    }
}

class DuplicateBinDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var loc = BinActions.pendingLocation;
        BinActions.pendingLocation = null;
        if (item.getId() == :save && loc != null) {
            BinActions.save(loc);
        }
    }
}

class RemoveBinDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        var index = item.getId() as Number;
        if (index < 0 || index >= BinActions.candidates.size()) {
            return;
        }
        var bin = BinActions.candidates[index];
        Bins.remove(bin);
        Feedback.toast(bin.kind == Bins.KIND_OWN ? Rez.Strings.BinDeleted : Rez.Strings.BinHidden);
    }
}
