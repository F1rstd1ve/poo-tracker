import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.WatchUi;

// Alarm screen of the Rückweg-Alarm: leads to the Sackdepot itself (arrow +
// distance) so the bag can be found; holding MENU opens the Aktionsmenü with
// "Aufgehoben" on top.
class AlarmView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        Settings.applyTouch();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Orange ring as alarm accent
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(8);
        dc.drawCircle(w / 2, h / 2, w / 2 - 5);

        var list = ReturnAlarm.triggeredDepots();
        var count = list.size();
        var title = count > 1
            ? Lang.format(WatchUi.loadResource(Rez.Strings.AlarmMany) as String, [count])
            : WatchUi.loadResource(Rez.Strings.AlarmOne) as String;
        dc.drawText(w / 2, h * 0.2, Graphics.FONT_MEDIUM, title,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var here = GpsService.position();
        var target = here != null ? nearestOf(here, list) : null;
        if (here != null && target != null) {
            var loc = DepotStore.location(target);
            var angle = GeoUtil.bearing(here, loc) - Heading.current();
            Draw.arrow(dc, w / 2, (h * 0.5).toNumber(), (w * 0.17).toNumber(), angle, Graphics.COLOR_WHITE);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.73, Graphics.FONT_LARGE,
                Format.shortDistance(GeoUtil.distance(here, loc)),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.87, Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.AlarmHint) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function nearestOf(here as Position.Location, list as Array<Dictionary>) as Dictionary? {
        var best = null;
        var bestDist = 0.0;
        for (var i = 0; i < list.size(); i++) {
            var d = GeoUtil.distance(here, DepotStore.location(list[i]));
            if (best == null || d < bestDist) {
                best = list[i];
                bestDist = d;
            }
        }
        return best;
    }
}

// Same keys as on the pages (START pauses, hold MENU opens the menu);
// UP/DOWN and LAP (back) hide the alarm screen without confirming it.
class AlarmDelegate extends PageDelegate {

    function initialize() {
        PageDelegate.initialize();
    }

    function onNextPage() as Boolean {
        dismiss();
        return true;
    }

    function onPreviousPage() as Boolean {
        dismiss();
        return true;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    // A tap on the alarm screen does nothing.
    function onScreenTap() as Void {
    }

    function onBack() as Boolean {
        dismiss();
        return true;
    }

    private function dismiss() as Void {
        ReturnAlarm.viewDismissed();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
