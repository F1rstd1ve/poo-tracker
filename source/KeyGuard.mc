import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Tells physical buttons from touch, like the official Garmin apps:
//  - START and a screen tap both arrive as the "select" behaviour (onSelect).
//    A tap must never start or pause.
//  - BACK/LAP and a swipe to the right both arrive as onBack. Only the button
//    may drop a bag (ADR 0005).
// Behaviours come before raw key events, so a handled onSelect/onBack never
// reaches onKey/onTap. Delegates therefore report raw presses (onKeyPressed)
// here; a behaviour counts as the button if that button was pressed shortly
// before, or is pressed right after (the other event order).
// If the device has never delivered any raw key press, every behaviour counts
// as the button, so the keys keep working even without onKeyPressed.
// No timer is used (the number of timers per app is limited).
module KeyGuard {

    const PRESS_BEFORE_MS = 3000;
    const PRESS_AFTER_MS = 400;
    const DEBOUNCE_MS = 300;

    var pressSeen as Boolean = false;
    var lastEnterMs as Number = -100000;
    var lastEscMs as Number = -100000;
    var pendingEnter as Method() as Void or Null = null;
    var pendingEnterMs as Number = -100000;
    var pendingEsc as Method() as Void or Null = null;
    var pendingEscMs as Number = -100000;
    var lastStartMs as Number = -100000;

    function notePress(key as Number) as Void {
        pressSeen = true;
        var now = System.getTimer();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            var action = pendingEnter;
            pendingEnter = null;
            if (action != null && now - pendingEnterMs < PRESS_AFTER_MS) {
                runStart(action, now);
            } else {
                lastEnterMs = now;
            }
        } else if (key == WatchUi.KEY_ESC || key == WatchUi.KEY_LAP) {
            var action = pendingEsc;
            pendingEsc = null;
            if (action != null && now - pendingEscMs < PRESS_AFTER_MS) {
                action.invoke();
            } else {
                lastEscMs = now;
            }
        }
    }

    // onSelect: START runs `start`, a tap runs `tap` (may be null).
    function select(start as Method() as Void, tap as Method() as Void or Null) as Void {
        var now = System.getTimer();
        if (!pressSeen || now - lastEnterMs < PRESS_BEFORE_MS) {
            lastEnterMs = -100000; // one press, one action
            pendingEnter = null;
            runStart(start, now);
            return;
        }
        pendingEnter = start;
        pendingEnterMs = now;
        if (tap != null) {
            tap.invoke();
        }
    }

    // Raw onKey(KEY_ENTER) on devices that do not map START to onSelect.
    function rawStart(start as Method() as Void) as Void {
        runStart(start, System.getTimer());
    }

    // The same press can arrive as select and as raw key: handle it once.
    function runStart(start as Method() as Void, now as Number) as Void {
        if (now - lastStartMs < DEBOUNCE_MS) {
            return;
        }
        lastStartMs = now;
        start.invoke();
    }

    // onBack: runs `action` only for the BACK/LAP button, not for a swipe.
    function back(action as Method() as Void) as Void {
        var now = System.getTimer();
        if (!pressSeen || now - lastEscMs < PRESS_BEFORE_MS) {
            lastEscMs = -100000;
            pendingEsc = null;
            action.invoke();
        } else {
            pendingEsc = action;
            pendingEscMs = now;
        }
    }
}
