import Toybox.Lang;
import Toybox.WatchUi;

// Aktionsmenü opened by holding MENU (ADR 0005; LAP itself drops a bag).
// Context-dependent, the most likely action is on top and preselected:
//   30 s after a drop                   -> Ablegen rückgängig
//   30 s after an automatic "Entsorgt"  -> Entsorgen rückgängig
//   Rückweg-Alarm ausgelöst             -> Aufgehoben
//   Sack aufgehoben, nicht entsorgt     -> Entsorgt
//   otherwise                           -> Sack ablegen
// At the end: Touch an/aus (like the Garmin activity options).
module ActionMenu {

    function open() as Void {
        var menu = new WatchUi.Menu2({:title => Rez.Strings.MenuTitle});

        var alarmCount = ReturnAlarm.triggeredDepots().size();
        var pickedCount = DepotStore.countIn(DepotStore.STATE_PICKED);
        var openCount = DepotStore.countIn(DepotStore.STATE_OPEN);

        if (DropBag.canUndo()) {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.UndoDrop, null, :undoDrop, null));
        }
        if (Disposal.canUndo()) {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.UndoDispose, null, :undo, null));
        }
        if (alarmCount > 0) {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.PickedUp, Format.bags(alarmCount), :pickUp, null));
        } else if (pickedCount > 0) {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.Disposed, Format.bags(pickedCount), :dispose, null));
        }
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.DropBag, null, :dropBag, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.AddBin, null, :addBin, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.AddDogBin, null, :addDogBin, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.RemoveBin, null, :removeBin, null));
        if (openCount > 0) {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.OpenDepots, Format.bags(openCount), :openDepots, null));
        }
        if (Pages.isEnabled(Pages.MAP)) {
            menu.addItem(new WatchUi.MenuItem(Rez.Strings.BrowseMap, null, :browse, null));
        }
        // Like the Garmin activity options: touch on/off during the walk.
        menu.addItem(Settings.touchMenuItem());

        WatchUi.pushView(menu, new ActionMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

class ActionMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :touch) {
            // Toggles in place, the menu stays open.
            Settings.setTouch((item as WatchUi.ToggleMenuItem).isEnabled());
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);

        if (id == :undoDrop) {
            DropBag.undo();
        } else if (id == :undo) {
            Disposal.undo();
        } else if (id == :pickUp) {
            ReturnAlarm.pickUp();
            Pages.map().refreshDepots();
            WalkSession.updateFit();
            Feedback.vibe();
            Feedback.toast(Rez.Strings.PickedUp);
            Pages.showBins();
        } else if (id == :dispose) {
            Disposal.dispose(false);
        } else if (id == :dropBag) {
            DropBag.start();
        } else if (id == :addBin) {
            BinActions.startAdd(Bins.KIND_GENERAL);
        } else if (id == :addDogBin) {
            BinActions.startAdd(Bins.KIND_DOG);
        } else if (id == :removeBin) {
            BinActions.openRemoveMenu();
        } else if (id == :openDepots) {
            DepotListMenu.open();
        } else if (id == :browse) {
            if (Pages.goTo(Pages.MAP)) {
                Pages.map().enterBrowse();
            }
        }
    }
}
