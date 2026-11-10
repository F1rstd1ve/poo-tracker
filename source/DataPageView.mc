import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// A configurable Datenseite (ADR 0003): layout with 1-4 fields, chosen in
// the Connect IQ phone app. Layouts as in Garmin's activity pages:
//   1: one big field
//   2: two rows
//   3: three rows
//   4: top / middle split / bottom
class DataPageView extends WatchUi.View {

    private var _page as Number;
    private var _timer as Timer.Timer?;

    function initialize(page as Number) {
        View.initialize();
        _page = page;
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
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var layout = Settings.pageLayout[_page];
        var f = Settings.pageFields[_page];
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        if (layout == 1) {
            drawField(dc, w / 2, h * 0.36, h * 0.54, f[0], Graphics.FONT_NUMBER_THAI_HOT);
        } else if (layout == 2) {
            var y = h / 2;
            dc.drawLine(0, y, w, y);
            drawField(dc, w / 2, h * 0.2, h * 0.34, f[0], Graphics.FONT_NUMBER_HOT);
            drawField(dc, w / 2, h * 0.6, h * 0.74, f[1], Graphics.FONT_NUMBER_HOT);
        } else if (layout == 3) {
            var y1 = (h * 0.37).toNumber();
            var y2 = (h * 0.65).toNumber();
            dc.drawLine(0, y1, w, y1);
            dc.drawLine(0, y2, w, y2);
            drawField(dc, w / 2, h * 0.15, h * 0.27, f[0], Graphics.FONT_NUMBER_MEDIUM);
            drawField(dc, w / 2, h * 0.42, h * 0.54, f[1], Graphics.FONT_NUMBER_MEDIUM);
            drawField(dc, w / 2, h * 0.7, h * 0.81, f[2], Graphics.FONT_NUMBER_MEDIUM);
        } else {
            var y1 = (h * 0.38).toNumber();
            var y2 = (h * 0.66).toNumber();
            dc.drawLine(0, y1, w, y1);
            dc.drawLine(0, y2, w, y2);
            dc.drawLine(w / 2, y1, w / 2, y2);
            drawField(dc, w / 2, h * 0.15, h * 0.27, f[0], Graphics.FONT_NUMBER_MEDIUM);
            drawField(dc, w * 0.28, h * 0.43, h * 0.54, f[1], Graphics.FONT_NUMBER_MEDIUM);
            drawField(dc, w * 0.72, h * 0.43, h * 0.54, f[2], Graphics.FONT_NUMBER_MEDIUM);
            drawField(dc, w / 2, h * 0.71, h * 0.81, f[3], Graphics.FONT_NUMBER_MEDIUM);
        }

        drawStatus(dc, w, h);
    }

    private function drawField(dc as Graphics.Dc, x as Numeric, labelY as Numeric, valueY as Numeric,
            field as Number, font as Graphics.FontType) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, labelY, Graphics.FONT_XTINY, Fields.label(field),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, valueY, font, Fields.value(field),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Top: GPS dot; PAUSE banner while paused.
    private function drawStatus(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var y = (h * 0.05).toNumber() + 4;
        dc.setColor(GpsService.statusColor(), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(w / 2, y, 5);

        if (WalkSession.isPaused()) {
            var bannerH = (h * 0.09).toNumber();
            var bannerY = (h * 0.5).toNumber() - bannerH / 2;
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_ORANGE);
            dc.fillRectangle(0, bannerY, w, bannerH);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, bannerY + bannerH / 2, Graphics.FONT_XTINY,
                WatchUi.loadResource(Rez.Strings.Paused) as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
