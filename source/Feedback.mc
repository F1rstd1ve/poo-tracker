import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Short haptic / on-screen confirmations.
module Feedback {

    function toast(textId as ResourceId) as Void {
        var text = WatchUi.loadResource(textId) as String;
        if (WatchUi has :showToast) {
            WatchUi.showToast(text, null);
        } else {
            System.println(text);
        }
    }

    // Rückweg-Alarm: two calm vibration pulses + a soft chime + brief backlight.
    // (AMOLED: never keep the backlight on, burn-in protection throws.)
    function alarm() as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(75, 400),
                new Attention.VibeProfile(0, 300),
                new Attention.VibeProfile(75, 400)
            ]);
        }
        chime();
        if (Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e) {
                // ignore: backlight not allowed right now
            }
        }
    }

    // Gentle rising three-note chime (A4 - C#5 - E5) instead of the shrill
    // system alarm tone. Falls back to the soft "message" tone on old devices.
    function chime() as Void {
        if (!Settings.alarmTone || !(Attention has :playTone)) {
            return;
        }
        if (Attention has :ToneProfile) {
            Attention.playTone({
                :toneProfile => [
                    new Attention.ToneProfile(440, 140),
                    new Attention.ToneProfile(0, 40),
                    new Attention.ToneProfile(554, 140),
                    new Attention.ToneProfile(0, 40),
                    new Attention.ToneProfile(659, 260)
                ],
                :repeatCount => 0
            });
        } else {
            Attention.playTone(Attention.TONE_MSG);
        }
        if (Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e) {
                // ignore: backlight not allowed right now
            }
        }
    }

    function vibe() as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, 200)]);
        }
    }
}
