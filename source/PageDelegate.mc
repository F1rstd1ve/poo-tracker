import Toybox.Lang;
import Toybox.WatchUi;

// Input on every page of a running Spaziergang.
//  START     -> pause (opens the pause menu) / resume when paused
//  LAP       -> Sack ablegen at once (ADR 0005); on the map while exploring:
//               back to follow. A swipe to the right does nothing (LapKey).
//  hold MENU -> Aktionsmenü (long press on UP)
//  UP/DOWN   -> previous/next page
//  Tap       -> on the Kartenseite: explore mode (Garmin pan/zoom)
class PageDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // START arrives as raw key or as "select" (see StartKey); a screen tap
    // must never pause the walk.
    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_ENTER) {
            if (StartKey.accept()) {
                onStartKey();
            }
            return true;
        }
        return false;
    }

    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        LapKey.notePress(keyEvent.getKey());
        return false;
    }

    function onSelect() as Boolean {
        if (StartKey.acceptSelect()) {
            onStartKey();
        }
        return true;
    }

    function onNextPage() as Boolean {
        Pages.next();
        return true;
    }

    function onPreviousPage() as Boolean {
        Pages.previous();
        return true;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        StartKey.noteTap();
        if (Pages.isMap()) {
            if (!Pages.map().isBrowsing()) {
                Pages.map().enterBrowse();
                return true;
            }
            // Exploring: leave the tap to Garmin's map controls.
            return false;
        }
        return true;
    }

    function onBack() as Boolean {
        if (Pages.isMap() && Pages.map().isBrowsing()) {
            Pages.map().enterFollow();
            return true;
        }
        LapKey.resolve(method(:onLapButton));
        return true;
    }

    function onLapButton() as Void {
        DropBag.start();
    }

    function onMenu() as Boolean {
        ActionMenu.open();
        return true;
    }

    private function onStartKey() as Void {
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
