import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;
import Toybox.WatchUi;

// Mülleimer-Führung: big compass arrow + distance to the target bin (nearest,
// Hundekot-Behälter preferred within +20 m); every bin within 100 m as a small
// marker at the screen edge in its direction.
class BinGuideView extends WatchUi.View {

    private const EDGE_RADIUS_M = 100.0;

    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
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
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.13, Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.BinGuideTitle) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var here = GpsService.position();
        if (here == null) {
            centerText(dc, cx, cy, Rez.Strings.WaitingForGps, Graphics.COLOR_YELLOW);
            return;
        }
        var p = Bins.degrees(here);
        var heading = Heading.current();
        var target = Bins.target(p[0], p[1]);

        // Edge markers for all bins within 100 m
        var ring = (w / 2 - 14).toFloat();
        var near = Bins.within(p[0], p[1], EDGE_RADIUS_M);
        for (var i = 0; i < near.size(); i++) {
            var b = near[i];
            var a = Bins.bearing(p[0], p[1], b) - heading;
            var x = (cx + ring * Math.sin(a)).toNumber();
            var y = (cy - ring * Math.cos(a)).toNumber();
            dc.setColor(kindColor(b.kind), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 7);
            if (b == target) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawCircle(x, y, 10);
            }
        }

        if (target == null) {
            centerText(dc, cx, cy, Rez.Strings.NoBinKnown, Graphics.COLOR_LT_GRAY);
        } else {
            var angle = Bins.bearing(p[0], p[1], target) - heading;
            Draw.arrow(dc, cx, (h * 0.46).toNumber(), (w * 0.17).toNumber(), angle, kindColor(target.kind));
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.69, Graphics.FONT_LARGE,
                Format.shortDistance(Bins.dist(p[0], p[1], target.lat, target.lon)),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.8, Graphics.FONT_XTINY,
                WatchUi.loadResource(BinActions.kindLabel(target.kind)) as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // OSM status, subtle
        var status = null;
        if (!Consent.online()) {
            status = Rez.Strings.OnlineOffShort;
        } else if (OsmLoader.status == OsmLoader.STATUS_LOADING) {
            status = Rez.Strings.OsmLoading;
        } else if (OsmLoader.status == OsmLoader.STATUS_OFFLINE) {
            status = Rez.Strings.OsmOffline;
        }
        if (status != null) {
            var text = WatchUi.loadResource(status) as String;
            if (OsmLoader.status == OsmLoader.STATUS_OFFLINE && OsmLoader.lastCode != 0) {
                text += " (" + OsmLoader.lastCode.toString() + ")";
            }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.89, Graphics.FONT_XTINY, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function centerText(dc as Graphics.Dc, cx as Number, cy as Number, text as ResourceId,
            color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_SMALL, WatchUi.loadResource(text) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    static function kindColor(kind as Number) as Graphics.ColorType {
        return kind == Bins.KIND_OSM_DOG ? 0x0090D0 : Graphics.COLOR_GREEN;
    }
}
