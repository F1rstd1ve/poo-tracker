import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

// "Mülleimer anlegen" / "Hundekot-Behälter anlegen" / "Mülleimer entfernen"
// from the Aktionsmenü. With "Teilen" every change becomes a Beitrag for the
// Gassi-Server (ADR 0006).
module BinActions {

    const REMOVE_RADIUS_M = 100.0;

    var pendingKind as Number = Bins.KIND_GENERAL;
    var pendingLocation as Position.Location? = null;
    var pendingImprecise as Boolean = false;
    var pendingBin as Bin? = null;
    var candidates as Array<Bin> = [] as Array<Bin>;

    function startAdd(kind as Number) as Void {
        pendingKind = kind;
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
        pendingImprecise = imprecise;
        // Same bin = same kind within 8 m (a dog-waste bin next to a normal
        // bin are two bins).
        var existing = Bins.sameKindWithin(p[0], p[1], pendingKind, Bins.SAME_BIN_M);
        if (existing != null && !existing.confirmed && !imprecise && Consent.given()
                && existing.origin != Bins.ORIGIN_OSM) {
            // Back at an unconfirmed bin: confirm it instead of a duplicate
            // (ADR 0006). An own one only 20 h after adding it.
            if (existing.origin == Bins.ORIGIN_OWN && !Bins.ownConfirmable(existing.src)) {
                Feedback.toast(Rez.Strings.ConfirmLater);
                return;
            }
            pendingBin = existing;
            var ask = new WatchUi.Menu2({:title => Rez.Strings.StillThere});
            ask.addItem(new WatchUi.MenuItem(Rez.Strings.ConfirmBin, null, :confirm, null));
            ask.addItem(new WatchUi.MenuItem(Rez.Strings.Cancel, null, :cancel, null));
            WatchUi.pushView(ask, new ConfirmBinDelegate(), WatchUi.SLIDE_UP);
            return;
        }
        if (existing != null) {
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
        var ref = Bins.addOwn(loc, pendingKind);
        var p = Bins.degrees(loc);
        ShareQueue.addBin(ref, pendingKind, p[0], p[1], pendingImprecise);
        Feedback.vibe();
        Feedback.toast(pendingKind == Bins.KIND_DOG ? Rez.Strings.DogBinSaved : Rez.Strings.BinSaved);
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
                label(b), i, null));
        }
        WatchUi.pushView(menu, new RemoveBinDelegate(), WatchUi.SLIDE_LEFT);
    }

    function kindLabel(kind as Number) as ResourceId {
        return kind == Bins.KIND_DOG ? Rez.Strings.KindDog : Rez.Strings.KindGeneral;
    }

    // "Hundekot-Behälter" / "Mülleimer · unbestätigt"
    function label(bin as Bin) as String {
        var text = WatchUi.loadResource(kindLabel(bin.kind)) as String;
        if (!bin.confirmed) {
            text += " · " + (WatchUi.loadResource(Rez.Strings.Unconfirmed) as String);
        }
        return text;
    }

    // Own unconfirmed bins are deleted; everything else is a Meldung
    // (gone here at once, for everyone after 2 Meldungen).
    function remove(bin as Bin) as Void {
        var toast = Rez.Strings.BinReported;
        if (bin.origin == Bins.ORIGIN_OWN) {
            ShareQueue.ownRemoved(bin);
            if (!bin.confirmed) {
                toast = Rez.Strings.BinDeleted;
            }
        } else if (bin.origin == Bins.ORIGIN_SHARED) {
            ShareQueue.report(bin, Bins.shSid[bin.src]);
        } else {
            ShareQueue.report(bin, 0);
        }
        if (!Consent.given() && bin.origin != Bins.ORIGIN_OWN) {
            toast = Rez.Strings.BinHidden;
        }
        Bins.remove(bin);
        Feedback.toast(toast);
    }
}

// "Ist noch da – bestätigen?"
class ConfirmBinDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var bin = BinActions.pendingBin;
        BinActions.pendingBin = null;
        if (item.getId() != :confirm || bin == null) {
            return;
        }
        if (bin.origin == Bins.ORIGIN_SHARED) {
            ShareQueue.confirm(Bins.shSid[bin.src]);
            Bins.confirmShared(bin.src);
        } else {
            ShareQueue.confirm(Bins.ownSid[bin.src]);
        }
        Feedback.vibe();
        Feedback.toast(Rez.Strings.BinConfirmed);
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
        BinActions.remove(BinActions.candidates[index]);
    }
}
