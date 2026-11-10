import Toybox.Lang;
import Toybox.WatchUi;

// "Offene Sackdepots": every open depot with distance and age; selecting one
// asks whether to delete it. Nothing is ever deleted automatically.
module DepotListMenu {

    function open() as Void {
        var menu = new WatchUi.Menu2({:title => Rez.Strings.OpenDepots});
        var here = GpsService.position();
        var list = DepotStore.inState(DepotStore.STATE_OPEN);
        for (var i = 0; i < list.size(); i++) {
            var depot = list[i];
            var label = here != null
                ? Format.shortDistance(GeoUtil.distance(here, DepotStore.location(depot)))
                : "?";
            menu.addItem(new WatchUi.MenuItem(label, Format.age(DepotStore.age(depot)), DepotStore.id(depot), null));
        }
        WatchUi.pushView(menu, new DepotListDelegate(), WatchUi.SLIDE_LEFT);
    }
}

class DepotListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var depotId = item.getId() as Number;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.pushView(
            new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.DeleteDepotConfirm) as String),
            new DeleteDepotDelegate(depotId),
            WatchUi.SLIDE_IMMEDIATE);
    }
}

class DeleteDepotDelegate extends WatchUi.ConfirmationDelegate {

    private var _depotId as Number;

    function initialize(depotId as Number) {
        ConfirmationDelegate.initialize();
        _depotId = depotId;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            DepotStore.removeById(_depotId);
            ReturnAlarm.forget(_depotId);
            Pages.map().refreshDepots();
            WalkSession.updateFit();
            Feedback.toast(Rez.Strings.DepotDeleted);
        }
        return true;
    }
}
