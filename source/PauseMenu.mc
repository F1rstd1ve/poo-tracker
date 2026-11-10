import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Pause menu after START, like the native Walk app:
// Fortsetzen / Speichern / Verwerfen. BACK leaves it and stays paused.
module PauseMenu {

    var exitTimer as Timer.Timer? = null;

    function open() as Void {
        var menu = new WatchUi.Menu2({:title => Rez.Strings.Paused});
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.Resume, null, :resume, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.Save, null, :save, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.Discard, null, :discard, null));
        WatchUi.pushView(menu, new PauseMenuDelegate(), WatchUi.SLIDE_UP);
    }

    // Picked-up bags that were not marked as disposed are assumed taken home.
    function saveAndExit() as Void {
        var ok = WalkSession.save();
        DepotStore.removeInState(DepotStore.STATE_PICKED);
        Feedback.vibe();
        Feedback.toast(ok ? Rez.Strings.Saved : Rez.Strings.SaveFailed);
        exitSoon();
    }

    // Leave the app shortly after a final message so the toast is readable.
    function exitSoon() as Void {
        var t = new Timer.Timer();
        t.start(new Lang.Method(PauseMenu, :exitNow), 1500, false);
        exitTimer = t;
    }

    function exitNow() as Void {
        System.exit();
    }
}

class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WalkSession.resume();
            Feedback.vibe();
        } else if (id == :save) {
            var open = DepotStore.countIn(DepotStore.STATE_OPEN);
            if (open > 0) {
                // Spec: warn before finishing with open Sackdepots; they stay stored.
                var text = open == 1
                    ? WatchUi.loadResource(Rez.Strings.OpenBagsWarnOne) as String
                    : Lang.format(WatchUi.loadResource(Rez.Strings.OpenBagsWarnMany) as String, [open]);
                WatchUi.pushView(new WatchUi.Confirmation(text), new SaveAnywayDelegate(), WatchUi.SLIDE_IMMEDIATE);
            } else {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                PauseMenu.saveAndExit();
            }
        } else if (id == :discard) {
            WatchUi.pushView(
                new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.DiscardConfirm) as String),
                new DiscardConfirmDelegate(),
                WatchUi.SLIDE_IMMEDIATE);
        }
    }
}

class SaveAnywayDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            PauseMenu.saveAndExit();
        }
        return true;
    }
}

class DiscardConfirmDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            WalkSession.discard();
            System.exit();
        }
        return true;
    }
}
