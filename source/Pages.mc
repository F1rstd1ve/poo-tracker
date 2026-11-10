import Toybox.Lang;
import Toybox.WatchUi;

// The page carousel of a running Spaziergang. UP/DOWN cycle through the
// enabled pages: Datenseite 1-3 -> Mülleimer-Führung -> Kartenseite.
// Which pages exist comes from the settings (step 6); at least Datenseite 1
// is always shown.
module Pages {

    // Page codes: 0..2 = Datenseite 1..3
    const BINS = 10;
    const MAP = 11;

    var entries as Array<Number> = [0] as Array<Number>;
    var index as Number = 0;
    var previousCode as Number = 0;
    var dataViews as Array<DataPageView> = [] as Array<DataPageView>;
    var binView as BinGuideView? = null;
    var mapView as MapPageView? = null;

    function setup() as Void {
        dataViews = [new DataPageView(0), new DataPageView(1), new DataPageView(2)] as Array<DataPageView>;
        binView = new BinGuideView();
        mapView = new MapPageView();
        rebuild();
    }

    // Recompute the enabled pages, keeping the current page if it still exists.
    function rebuild() as Void {
        var oldCode = entries.size() > 0 ? currentCode() : 0;
        var list = [] as Array<Number>;
        for (var p = 0; p < 3; p++) {
            if (Settings.pageOn[p]) {
                list.add(p);
            }
        }
        if (list.size() == 0) {
            list.add(0);
        }
        if (Settings.binsPage) {
            list.add(BINS);
        }
        if (Settings.mapPage) {
            list.add(MAP);
        }
        entries = list;
        var i = entries.indexOf(oldCode);
        index = i >= 0 ? i : 0;
    }

    function currentCode() as Number {
        return entries[index];
    }

    function map() as MapPageView {
        return mapView as MapPageView;
    }

    function isMap() as Boolean {
        return currentCode() == MAP;
    }

    function isEnabled(code as Number) as Boolean {
        return entries.indexOf(code) >= 0;
    }

    function current() as WatchUi.View {
        var code = currentCode();
        if (code == MAP) {
            return mapView as MapPageView;
        }
        if (code == BINS) {
            return binView as BinGuideView;
        }
        return dataViews[code];
    }

    function show(transition as WatchUi.SlideType) as Void {
        WatchUi.switchToView(current(), new PageDelegate(), transition);
    }

    function showFirst() as Void {
        index = 0;
        show(WatchUi.SLIDE_IMMEDIATE);
    }

    // Switch to the page with `code`, if enabled.
    function goTo(code as Number) as Boolean {
        var i = entries.indexOf(code);
        if (i < 0) {
            return false;
        }
        if (i != index) {
            index = i;
            show(WatchUi.SLIDE_IMMEDIATE);
        }
        return true;
    }

    function next() as Void {
        index = (index + 1) % entries.size();
        show(WatchUi.SLIDE_UP);
    }

    function previous() as Void {
        index = (index + entries.size() - 1) % entries.size();
        show(WatchUi.SLIDE_DOWN);
    }

    // After "Aufgehoben": jump to the Mülleimer-Führung, remember where we were.
    function showBins() as Void {
        var code = currentCode();
        if (code != BINS && isEnabled(BINS)) {
            previousCode = code;
            goTo(BINS);
        }
    }

    // After "Entsorgt": back to the page shown before.
    function returnFromBins() as Void {
        if (currentCode() == BINS && previousCode != BINS) {
            goTo(previousCode);
        }
    }
}
