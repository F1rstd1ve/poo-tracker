import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The BACK/LAP button and a swipe to the right on the touchscreen both arrive
// as the "back" behaviour (onBack). During a Spaziergang only the button may
// drop a bag (ADR 0005), so delegates report raw key presses (onKeyPressed)
// here and let resolve() decide:
//  - BACK/LAP pressed shortly before the onBack -> button
//  - BACK/LAP pressed right after the onBack    -> button (other event order)
//  - no such press                              -> swipe, ignored
// If the device has never delivered any raw key press, every onBack counts as
// the button, so LAP keeps working even if onKeyPressed is not available.
// No timer is used (the number of timers per app is limited).
module LapKey {

    const PRESS_BEFORE_MS = 3000;
    const PRESS_AFTER_MS = 400;

    var pressSeen as Boolean = false;
    var lastPressMs as Number = -100000;
    var pending as Method() as Void or Null = null;
    var pendingMs as Number = -100000;

    function notePress(key as Number) as Void {
        pressSeen = true;
        if (key != WatchUi.KEY_ESC && key != WatchUi.KEY_LAP) {
            return;
        }
        var now = System.getTimer();
        var action = pending;
        pending = null;
        if (action != null && now - pendingMs < PRESS_AFTER_MS) {
            action.invoke();
        } else {
            lastPressMs = now;
        }
    }

    // Runs `action` if this onBack came from the button.
    function resolve(action as Method() as Void) as Void {
        var now = System.getTimer();
        if (!pressSeen || now - lastPressMs < PRESS_BEFORE_MS) {
            lastPressMs = -100000; // one press, one action
            pending = null;
            action.invoke();
        } else {
            pending = action;
            pendingMs = now;
        }
    }
}
