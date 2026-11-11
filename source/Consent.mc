import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;

// "Teilen" (ADR 0006): loading bins online and sharing own bins sends
// approximate positions to the Gassi-Server, so it needs an explicit opt-in
// (Garmin: no location collection by default). Asked once on first start,
// changeable on the start screen (hold MENU) and in the phone app (osm).
module Consent {

    const KEY = "consent";

    function asked() as Boolean {
        return Application.Storage.getValue(KEY) != null;
    }

    function given() as Boolean {
        return Application.Storage.getValue(KEY) == true;
    }

    // Switching sharing on creates the Kennung and queues own bins; switching
    // it off forgets the Kennung and unsent Beiträge (privacy policy).
    function set(value as Boolean) as Void {
        Application.Storage.setValue(KEY, value);
        if (value) {
            ShareQueue.onConsent();
        } else {
            ShareQueue.forget();
        }
    }

    // Online loading is allowed (consent and phone-app setting).
    function online() as Boolean {
        return given() && Settings.osm;
    }

    function ask() as Void {
        WatchUi.pushView(
            new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.ConsentQuestion) as String),
            new ConsentDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    // Opens the privacy policy on the phone.
    function openPrivacy() as Void {
        Communications.openWebPage(ServerConfig.PRIVACY_URL, null, null);
        Feedback.toast(Rez.Strings.SeePhone);
    }
}

class ConsentDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        var yes = response == WatchUi.CONFIRM_YES;
        Consent.set(yes);
        Feedback.toast(yes ? Rez.Strings.OnlineOn : Rez.Strings.OnlineOff);
        return true;
    }
}

// Start screen menu (hold MENU): online switch and privacy policy.
module StartMenu {

    function open() as Void {
        var menu = new WatchUi.Menu2({:title => Rez.Strings.SettingsTitle});
        menu.addItem(new WatchUi.ToggleMenuItem(Rez.Strings.OnlineBins, Rez.Strings.OnlineBinsSub,
            :online, Consent.given(), null));
        if (Consent.given()) {
            // "Geteilt 3 von 5" / "wartend 2 · Server 200"
            var code = ShareQueue.lastCode;
            menu.addItem(new WatchUi.MenuItem(
                Lang.format(WatchUi.loadResource(Rez.Strings.ShareCount) as String,
                    [Bins.sharedOwnCount(), Bins.ownLat.size()]),
                Lang.format(WatchUi.loadResource(Rez.Strings.ShareWaiting) as String,
                    [ShareQueue.size(), code == 0 ? "-" : code.toString()]),
                :share, null));
        }
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.Privacy, Rez.Strings.PrivacySub, :privacy, null));
        WatchUi.pushView(menu, new StartMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

class StartMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :online) {
            var on = (item as WatchUi.ToggleMenuItem).isEnabled();
            Consent.set(on);
            Feedback.toast(on ? Rez.Strings.OnlineOn : Rez.Strings.OnlineOff);
        } else if (id == :privacy) {
            Consent.openPrivacy();
        }
    }
}
