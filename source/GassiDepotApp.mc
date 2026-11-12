import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

// Entry point: start screen -> START -> page carousel of the Spaziergang.
// GPS runs from app start so the fix is ready (and keeps running while paused).
class GassiDepotApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        Settings.load();
        Settings.applyTouch();
        DepotStore.load();
        Bins.load();
        TileLoader.load();
        SharedLoader.load();
        ShareQueue.load();
        // Own bins from before Etappe B (or added without consent) are shared once.
        ShareQueue.enqueueUnshared();
        Pages.setup();
        Pages.map().refreshDepots();
        GpsService.start(method(:onPosition));
    }

    function onStop(state as Dictionary?) as Void {
        // Never lose a walk: if the app is closed while a session is open, save it.
        if (WalkSession.hasStarted()) {
            WalkSession.save();
        }
        GpsService.stop();
    }

    function onPosition(info as Position.Info) as Void {
        GpsService.lastInfo = info;
        var map = Pages.mapView;
        if (map != null) {
            map.onPosition(info);
        }
        var loc = info.position;
        if (loc == null || info.accuracy < Position.QUALITY_POOR) {
            return;
        }
        Bins.onPosition(loc);
        OsmLoader.check(loc);
        // Rückweg-Alarm and auto-"Entsorgt" run while a Spaziergang is open (also when paused).
        if (WalkSession.hasStarted()) {
            ReturnAlarm.update(loc);
            Disposal.update(info, loc);
        }
        WatchUi.requestUpdate();
    }

    // Settings changed in the Connect IQ phone app while the app runs.
    function onSettingsChanged() as Void {
        Settings.load();
        Settings.applyTouch();
        Pages.rebuild();
        GpsService.start(method(:onPosition));
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new StartView(), new StartDelegate()];
    }
}
