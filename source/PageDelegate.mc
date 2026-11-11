import Toybox.Lang;
import Toybox.WatchUi;

// Input on every page of a running Spaziergang, like the official apps:
//  START     -> pause (opens the pause menu) / resume when paused
//  LAP       -> Sack ablegen at once (ADR 0005)
//  hold MENU -> Aktionsmenü (long press on UP)
//  UP/DOWN   -> previous/next page
//  Tap       -> never starts or pauses; on the Kartenseite it opens
//               "Erkunden" (Garmin's own pan/zoom controls)
// While exploring the map every input except BACK goes to the Garmin map;
// BACK returns to "Folgen". Buttons and touch are told apart by KeyGuard.
class PageDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function browsing() as Boolean {
        return Pages.isMap() && Pages.map().isBrowsing();
    }

    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        KeyGuard.notePress(keyEvent.getKey());
        return false;
    }

    // Devices that deliver START as a raw key instead of "select".
    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (browsing()) {
            return false;
        }
        if (keyEvent.getKey() == WatchUi.KEY_ENTER) {
            KeyGuard.rawStart(method(:onStartKey));
            return true;
        }
        return false;
    }

    function onSelect() as Boolean {
        if (browsing()) {
            return false;
        }
        KeyGuard.select(method(:onStartKey), method(:onScreenTap));
        return true;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        if (browsing()) {
            return false;
        }
        onScreenTap();
        return true;
    }

    function onNextPage() as Boolean {
        if (browsing()) {
            return false;
        }
        Pages.next();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (browsing()) {
            return false;
        }
        Pages.previous();
        return true;
    }

    function onMenu() as Boolean {
        if (browsing()) {
            return false;
        }
        ActionMenu.open();
        return true;
    }

    function onBack() as Boolean {
        if (browsing()) {
            Pages.map().enterFollow();
            return true;
        }
        KeyGuard.back(method(:onLapButton));
        return true;
    }

    function onLapButton() as Void {
        DropBag.start();
    }

    // A touch on the screen: only the map reacts (opens "Erkunden").
    function onScreenTap() as Void {
        if (Pages.isMap() && !Pages.map().isBrowsing()) {
            Pages.map().enterBrowse();
        }
    }

    function onStartKey() as Void {
        if (WalkSession.isRecording()) {
            WalkSession.pause();
            Feedback.vibe();
            PauseMenu.open();
        } else if (WalkSession.isPaused()) {
            WalkSession.resume();
            Feedback.vibe();
            Feedback.toast(Rez.Strings.Resumed);
        }
        WatchUi.requestUpdate();
    }
}
