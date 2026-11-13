import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Start screen: GPS status and "START = Los". Like Garmin, starting is
// possible before GPS is ready. (Open-depot hint follows in step 4.)
class StartView extends WatchUi.View {

    private var _timer as Timer.Timer?;
    private var _icon as WatchUi.BitmapResource?;
    private var _consentShown as Boolean = false;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _icon = WatchUi.loadResource(Rez.Drawables.LauncherIcon) as WatchUi.BitmapResource;
    }

    function onShow() as Void {
        Settings.applyTouch();
        var t = new Timer.Timer();
        t.start(method(:tick), 1000, true);
        _timer = t;
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
    }

    function tick() as Void {
        // First start: ask for "Teilen" once (ADR 0006).
        if (!_consentShown && !Consent.asked()) {
            _consentShown = true;
            Consent.ask();
            return;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var icon = _icon;
        if (icon != null) {
            dc.drawBitmap((w - icon.getWidth()) / 2, (h * 0.14).toNumber(), icon);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.42, Graphics.FONT_MEDIUM,
            WatchUi.loadResource(Rez.Strings.AppName) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var ready = GpsService.hasUsableFix();
        dc.setColor(GpsService.statusColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.58, Graphics.FONT_SMALL,
            WatchUi.loadResource(ready ? Rez.Strings.GpsReady : Rez.Strings.WaitingForGps) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var openHint = openDepotHint();
        if (openHint != null) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.7, Graphics.FONT_XTINY, openHint,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.82, Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.StartHint) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "1 offenes Sackdepot · 340 m" (distance to the nearest one, if GPS is there).
    private function openDepotHint() as String? {
        var count = DepotStore.countIn(DepotStore.STATE_OPEN);
        if (count == 0) {
            return null;
        }
        var text = count == 1
            ? WatchUi.loadResource(Rez.Strings.StartOpenOne) as String
            : Lang.format(WatchUi.loadResource(Rez.Strings.StartOpenMany) as String, [count]);
        var here = GpsService.position();
        if (here != null) {
            var nearest = DepotStore.nearest(here, DepotStore.STATE_OPEN);
            if (nearest != null) {
                text += " · " + Format.shortDistance(GeoUtil.distance(here, DepotStore.location(nearest)));
            }
        }
        return text;
    }
}

// START begins the Spaziergang (a tap never does); BACK leaves the app.
class StartDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        KeyGuard.notePress(keyEvent.getKey());
        return false;
    }

    // Devices that deliver START as a raw key instead of "select".
    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_ENTER) {
            KeyGuard.rawStart(method(:begin));
            return true;
        }
        return false;
    }

    function onSelect() as Boolean {
        KeyGuard.select(method(:begin), null);
        return true;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function begin() as Void {
        if (WalkSession.hasStarted()) {
            return;
        }
        WalkSession.start();
        Feedback.vibe();
        Pages.showFirst();
    }

    // Hold MENU: online switch and privacy policy.
    function onMenu() as Boolean {
        StartMenu.open();
        return true;
    }

    function onBack() as Boolean {
        return false;
    }
}
