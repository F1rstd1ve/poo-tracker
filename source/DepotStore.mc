import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;

// Persistent list of Sackdepots (survives the end of a Spaziergang and app restarts).
// A depot is a Dictionary:
//   "id"  Number   unique id
//   "lat" Double   latitude (degrees)
//   "lon" Double   longitude (degrees)
//   "t"   Number   time dropped (epoch seconds)
//   "s"   Number   state: STATE_OPEN or STATE_PICKED (entsorgt = removed)
//   "imp" Boolean  dropped with imprecise GPS -> larger trigger radius
module DepotStore {

    const KEY = "depots";
    const STATE_OPEN = 0;
    const STATE_PICKED = 1;

    var depots as Array<Dictionary> = [] as Array<Dictionary>;
    var nextId as Number = 1;

    function load() as Void {
        var stored = Application.Storage.getValue(KEY);
        if (stored instanceof Array) {
            depots = stored as Array<Dictionary>;
        } else {
            depots = [] as Array<Dictionary>;
        }
        nextId = 1;
        for (var i = 0; i < depots.size(); i++) {
            var id = depots[i]["id"] as Number;
            if (id >= nextId) {
                nextId = id + 1;
            }
        }
    }

    function persist() as Void {
        Application.Storage.setValue(KEY, depots as Application.PropertyValueType);
    }

    function add(loc as Position.Location, imprecise as Boolean) as Dictionary {
        var deg = loc.toDegrees();
        var depot = {
            "id" => nextId,
            "lat" => deg[0],
            "lon" => deg[1],
            "t" => Time.now().value(),
            "s" => STATE_OPEN,
            "imp" => imprecise
        } as Dictionary;
        nextId++;
        depots.add(depot);
        persist();
        return depot;
    }

    function id(depot as Dictionary) as Number {
        return depot["id"] as Number;
    }

    function location(depot as Dictionary) as Position.Location {
        return new Position.Location({
            :latitude => depot["lat"] as Double,
            :longitude => depot["lon"] as Double,
            :format => :degrees
        });
    }

    function isImprecise(depot as Dictionary) as Boolean {
        return depot["imp"] == true;
    }

    // Seconds since the depot was dropped.
    function age(depot as Dictionary) as Number {
        return Time.now().value() - (depot["t"] as Number);
    }

    function inState(state as Number) as Array<Dictionary> {
        var result = [] as Array<Dictionary>;
        for (var i = 0; i < depots.size(); i++) {
            if (depots[i]["s"] == state) {
                result.add(depots[i]);
            }
        }
        return result;
    }

    function countIn(state as Number) as Number {
        return inState(state).size();
    }

    function setState(ids as Array<Number>, state as Number) as Void {
        for (var i = 0; i < depots.size(); i++) {
            if (ids.indexOf(depots[i]["id"] as Number) >= 0) {
                depots[i]["s"] = state;
            }
        }
        persist();
    }

    function removeById(depotId as Number) as Void {
        for (var i = depots.size() - 1; i >= 0; i--) {
            if (depots[i]["id"] == depotId) {
                depots.remove(depots[i]);
            }
        }
        persist();
    }

    function removeInState(state as Number) as Void {
        var keep = [] as Array<Dictionary>;
        for (var i = 0; i < depots.size(); i++) {
            if (depots[i]["s"] != state) {
                keep.add(depots[i]);
            }
        }
        depots = keep;
        persist();
    }

    // Nearest depot of `state` to `here`, or null.
    function nearest(here as Position.Location, state as Number) as Dictionary? {
        var best = null;
        var bestDist = 0.0;
        var list = inState(state);
        for (var i = 0; i < list.size(); i++) {
            var d = GeoUtil.distance(here, location(list[i]));
            if (best == null || d < bestDist) {
                best = list[i];
                bestDist = d;
            }
        }
        return best;
    }
}
