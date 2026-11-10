import Toybox.Lang;
import Toybox.System;

// The START button reaches an app either as a raw key (onKey, KEY_ENTER) or
// as the "select" behaviour (onSelect) - on the Epix Pro it arrives as select.
// A screen tap can also produce onSelect, so delegates call noteTap() in onTap
// and ignore a select that directly follows a tap. A debounce prevents the
// same press from being handled twice when both events arrive.
module StartKey {

    const TAP_GUARD_MS = 400;
    const DEBOUNCE_MS = 300;

    var lastTapMs as Number = -100000;
    var lastHandledMs as Number = -100000;

    function noteTap() as Void {
        lastTapMs = System.getTimer();
    }

    // True if this select event should be treated as a START press.
    function acceptSelect() as Boolean {
        return System.getTimer() - lastTapMs >= TAP_GUARD_MS && accept();
    }

    // True if a START press may be handled now (not a duplicate).
    function accept() as Boolean {
        var now = System.getTimer();
        if (now - lastHandledMs < DEBOUNCE_MS) {
            return false;
        }
        lastHandledMs = now;
        return true;
    }
}
