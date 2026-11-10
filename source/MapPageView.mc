import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

// Kartenseite: own track, open Sackdepots and nearby Mülleimer.
//
// What this prototype must prove on the real Epix Pro:
//  - Follow mode: the map follows the user (MapTrackView, MAP_MODE_PREVIEW).
//  - Our own marker bitmaps for bag depots, bins and dog-waste bins.
//  - The walked track as a polyline.
//  - Explore mode: Garmin's standard pan/zoom (MAP_MODE_BROWSE), entered by tap
//    or the action menu, left with BACK.
//  - Whether text drawn over the map shows up.
// Known forum bugs to watch for: touch overriding preview mode, zoom resetting
// on setMapMarker/setPolyline, +/- buttons appearing inconsistently.
class MapPageView extends WatchUi.MapTrackView {

    // Add a track point only after moving at least this far (keeps the polyline small).
    private const TRACK_MIN_STEP_M = 10.0;
    // Thin the polyline beyond this many points.
    private const TRACK_MAX_POINTS = 400;
    // Width of the visible map in follow mode (spec: about 300 m).
    private const FOLLOW_WIDTH_M = 300.0;

    private var _track as WatchUi.MapPolyline;
    private var _trackPoints as Number = 0;
    private var _lastTrackPoint as Position.Location?;
    private var _trackDirty as Boolean = false;

    private var _depotMarkers as Array<WatchUi.MapMarker> = [] as Array<WatchUi.MapMarker>;
    private var _binMarkers as Array<WatchUi.MapMarker> = [] as Array<WatchUi.MapMarker>;

    private var _browsing as Boolean = false;

    private var _depotIcon as WatchUi.BitmapResource;
    private var _binIcon as WatchUi.BitmapResource;
    private var _dogBinIcon as WatchUi.BitmapResource;

    function initialize() {
        MapTrackView.initialize();
        _depotIcon = WatchUi.loadResource(Rez.Drawables.MarkerDepot) as WatchUi.BitmapResource;
        _binIcon = WatchUi.loadResource(Rez.Drawables.MarkerBin) as WatchUi.BitmapResource;
        _dogBinIcon = WatchUi.loadResource(Rez.Drawables.MarkerDogBin) as WatchUi.BitmapResource;

        _track = newTrack();
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        setScreenVisibleArea(0, 0, dc.getWidth(), dc.getHeight());
        showAround(initialCenter());
    }

    // Map area of about FOLLOW_WIDTH_M across, centered on `center`.
    private function showAround(center as Position.Location) as Void {
        var half = FOLLOW_WIDTH_M / 2;
        var diag = (half * Math.sqrt(2)).toFloat();
        var topLeft = GeoUtil.project(center, (Math.PI * 1.75).toFloat(), diag);
        var bottomRight = GeoUtil.project(center, (Math.PI * 0.75).toFloat(), diag);
        setMapVisibleArea(topLeft, bottomRight);
    }

    // Last known position, or Vienna as a neutral fallback before the first fix.
    private function initialCenter() as Position.Location {
        var info = Position.getInfo();
        if (info.position != null) {
            return info.position as Position.Location;
        }
        return new Position.Location({:latitude => 48.2085, :longitude => 16.3731, :format => :degrees});
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        MapTrackView.onUpdate(dc);
        drawStatusOverlay(dc);
    }

    // --- Position updates -------------------------------------------------

    function onPosition(info as Position.Info) as Void {
        var loc = info.position;
        if (loc == null || info.accuracy < Position.QUALITY_POOR) {
            WatchUi.requestUpdate();
            return;
        }
        appendTrackPoint(loc);
        WatchUi.requestUpdate();
    }

    private function appendTrackPoint(loc as Position.Location) as Void {
        var last = _lastTrackPoint;
        if (last != null && GeoUtil.distance(last, loc) < TRACK_MIN_STEP_M) {
            return;
        }
        if (_trackPoints >= TRACK_MAX_POINTS) {
            // Prototype: start a fresh segment rather than thinning.
            _track = newTrack();
            _trackPoints = 0;
        }
        _track.addLocation(loc);
        _trackPoints++;
        _lastTrackPoint = loc;
        _trackDirty = true;
        // Pushing a new polyline is said to reset the user's zoom on some
        // devices, so while exploring we defer it until BACK.
        if (!_browsing) {
            flushTrack();
        }
    }

    private function flushTrack() as Void {
        if (_trackDirty) {
            setPolyline(_track);
            _trackDirty = false;
        }
    }

    private function newTrack() as WatchUi.MapPolyline {
        var track = new WatchUi.MapPolyline();
        track.setColor(Graphics.COLOR_BLUE);
        track.setWidth(4);
        return track;
    }

    // --- Markers ----------------------------------------------------------

    // Markers for all open Sackdepots (call after any depot change).
    function refreshDepots() as Void {
        var open = DepotStore.inState(DepotStore.STATE_OPEN);
        _depotMarkers = [] as Array<WatchUi.MapMarker>;
        for (var i = 0; i < open.size(); i++) {
            var marker = new WatchUi.MapMarker(DepotStore.location(open[i]));
            marker.setIcon(_depotIcon, _depotIcon.getWidth() / 2, _depotIcon.getHeight() / 2);
            _depotMarkers.add(marker);
        }
        pushMarkers();
    }

    // Markers for the nearest bins (max. 40 within 500 m of the current position).
    function refreshBins() as Void {
        var here = GpsService.position();
        _binMarkers = [] as Array<WatchUi.MapMarker>;
        if (here != null) {
            var p = Bins.degrees(here);
            var list = Bins.nearestN(p[0], p[1], 40, 500.0);
            for (var i = 0; i < list.size(); i++) {
                var icon = list[i].kind == Bins.KIND_OSM_DOG ? _dogBinIcon : _binIcon;
                var marker = new WatchUi.MapMarker(list[i].location());
                marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
                _binMarkers.add(marker);
            }
        }
        pushMarkers();
    }

    private function pushMarkers() as Void {
        var all = [] as Array<WatchUi.MapMarker>;
        all.addAll(_binMarkers);
        all.addAll(_depotMarkers);
        if (all.size() > 0) {
            setMapMarker(all);
        } else {
            // setMapMarker() throws on an empty array; clear() also drops the
            // track, so put it back.
            clear();
            if (_trackPoints > 0) {
                setPolyline(_track);
            }
        }
        WatchUi.requestUpdate();
    }

    // --- Follow / explore ---------------------------------------------------

    function isBrowsing() as Boolean {
        return _browsing;
    }

    function enterBrowse() as Void {
        _browsing = true;
        setMapMode(WatchUi.MAP_MODE_BROWSE);
        System.println("map: enter browse");
        WatchUi.requestUpdate();
    }

    function enterFollow() as Void {
        _browsing = false;
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
        flushTrack();
        System.println("map: back to follow");
        WatchUi.requestUpdate();
    }

    // --- Overlay ------------------------------------------------------------

    // GPS quality dot at the top, like on the Datenseiten.
    private function drawStatusOverlay(dc as Graphics.Dc) as Void {
        var y = (dc.getHeight() * 0.05).toNumber() + 4;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dc.getWidth() / 2, y, 7);
        dc.setColor(GpsService.statusColor(), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dc.getWidth() / 2, y, 5);
    }
}
