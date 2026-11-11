import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Stop screen after START, like the official activity apps (ADR 0007): the
// native Menu2 with the red menu theme (red ring), icons and the elapsed time
// as title: Weiter / Speichern / Verwerfen. BACK leaves it and stays paused
// (orange PAUSE banner on the pages).
// "Später fortsetzen" is not offered: a Connect IQ app cannot keep a recording
// across leaving the app (no Resume Later for Connect IQ activities).
module PauseMenu {

    var exitTimer as Timer.Timer? = null;

    function open() as Void {
        var options = {:title => new PauseTitle()};
        if (WatchUi has :MENU_THEME_RED) {
            options[:theme] = WatchUi.MENU_THEME_RED;
        }
        var menu = new WatchUi.Menu2(options);
        menu.addItem(item(:resume, Rez.Strings.Resume, Rez.Drawables.IconResume));
        menu.addItem(item(:save, Rez.Strings.Save, Rez.Drawables.IconSave));
        menu.addItem(item(:discard, Rez.Strings.Discard, Rez.Drawables.IconDiscard));
        WatchUi.pushView(menu, new PauseMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function item(id as Symbol, label as ResourceId, icon as ResourceId) as WatchUi.MenuItem {
        return new WatchUi.IconMenuItem(WatchUi.loadResource(label) as String, null, id,
            new MenuIcon(icon), null);
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

// Title: the elapsed time, like the native stop screen.
class PauseTitle extends WatchUi.Drawable {

    function initialize() {
        Drawable.initialize({});
    }

    function draw(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_MEDIUM, timerText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Menu icon centred in the area the menu gives it. (A BitmapResource passed
// directly crashes Menu2 on the Epix Pro simulator.)
class MenuIcon extends WatchUi.Drawable {

    private var _bitmap as WatchUi.BitmapResource;

    function initialize(icon as ResourceId) {
        Drawable.initialize({});
        _bitmap = WatchUi.loadResource(icon) as WatchUi.BitmapResource;
    }

    function draw(dc as Graphics.Dc) as Void {
        dc.drawBitmap(locX + (dc.getWidth() - _bitmap.getWidth()) / 2, locY + (dc.getHeight() - _bitmap.getHeight()) / 2, _bitmap);
    }
}

function timerText() as String {
    var info = Activity.getActivityInfo();
    return info != null && info.timerTime != null ? Format.duration(info.timerTime as Number) : "0:00";
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
