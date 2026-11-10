import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Small drawing helpers.
module Draw {

    // Filled arrow centered at (cx, cy), `size` = distance center -> tip,
    // pointing `angle` radians clockwise from screen-up.
    function arrow(dc as Graphics.Dc, cx as Number, cy as Number, size as Number,
            angle as Float, color as Graphics.ColorType) as Void {
        var shape = [[0.0, -1.0], [0.62, 0.75], [0.0, 0.38], [-0.62, 0.75]];
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);
        var points = [] as Array<Graphics.Point2D>;
        for (var i = 0; i < shape.size(); i++) {
            var x = shape[i][0] * size;
            var y = shape[i][1] * size;
            points.add([
                (cx + x * cos - y * sin).toNumber(),
                (cy + x * sin + y * cos).toNumber()
            ] as Graphics.Point2D);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
    }
}
