import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Stop screen after START, drawn like the native stop screen of the Garmin
// activities (ADR 0007, photo of the Epix Pro "Gehen" activity): thin red
// ring, elapsed time as large title, white icons with left-aligned labels,
// a white bar marks the selected entry: Weiter / Speichern / Verwerfen.
// (Menu2 with MENU_THEME_RED shows no ring for apps on the Epix Pro.)
// BACK leaves it and stays paused (orange PAUSE banner on the pages).
// "Später fortsetzen" is not offered: a Connect IQ app cannot keep a recording
// across leaving the app (no Resume Later for Connect IQ activities).
module PauseMenu {

    const RED = 0xE5202E;

    var exitTimer as Timer.Timer? = null;

    function open() as Void {
        var h = System.getDeviceSettings().screenHeight;
        var menu = new WatchUi.CustomMenu((h * 0.15).toNumber(), Graphics.COLOR_BLACK, {
            :title => new PauseTitle(),
            :foreground => new PauseRing(),
            :titleItemHeight => (h * 0.27).toNumber()
        });
        menu.addItem(new PauseItem(:resume, Rez.Strings.Resume, Rez.Drawables.IconResume));
        menu.addItem(new PauseItem(:save, Rez.Strings.Save, Rez.Drawables.IconSave));
        menu.addItem(new PauseItem(:discard, Rez.Strings.Discard, Rez.Drawables.IconDiscard));
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

// Thin red ring inside the screen edge, like the native stop screen.
class PauseRing extends WatchUi.Drawable {

    function initialize() {
        Drawable.initialize({});
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var r = (w < h ? w : h) / 2;
        dc.setColor(PauseMenu.RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((r * 0.025).toNumber() + 2);
        dc.drawCircle(w / 2, h / 2, (r * 0.93).toNumber());
    }
}

// Title: the elapsed time, large, like the native stop screen.
class PauseTitle extends WatchUi.Drawable {

    function initialize() {
        Drawable.initialize({});
    }

    function draw(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.62, Graphics.FONT_NUMBER_MILD, timerText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

function timerText() as String {
    var info = Activity.getActivityInfo();
    return info != null && info.timerTime != null ? Format.duration(info.timerTime as Number) : "0:00";
}

// Entry: white icon, left-aligned white label; the selected one gets a white
// bar on the left.
class PauseItem extends WatchUi.CustomMenuItem {

    private var _label as String;
    private var _icon as WatchUi.BitmapResource;

    function initialize(id as Symbol, label as ResourceId, icon as ResourceId) {
        CustomMenuItem.initialize(id, {});
        _label = WatchUi.loadResource(label) as String;
        _icon = WatchUi.loadResource(icon) as WatchUi.BitmapResource;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cy = h / 2;
        if (isFocused()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle((w * 0.12).toNumber(), cy - (h * 0.32).toNumber(), 5, (h * 0.64).toNumber(), 2);
        }
        dc.drawBitmap((w * 0.2).toNumber(), cy - _icon.getHeight() / 2, _icon);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText((w * 0.2).toNumber() + _icon.getWidth() + (w * 0.03).toNumber(), cy, Graphics.FONT_MEDIUM,
            _label, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
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
