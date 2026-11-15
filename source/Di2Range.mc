import Toybox.Application;
import Toybox.Lang;

// Estimates the remaining Di2 battery range. It starts from Shimano's figure
// (about 1000 km on a full charge, so 10 km per percent) and learns in the
// background how far THIS bike really rides per percent; the learned value
// gradually replaces the default.
//
// Shimano reports the battery in coarse steps (100, 90, 80 ... 25, 20, 15, 10, 5, 0),
// so we need at least MIN_DROP percent and MIN_KM since the last charge.
class Di2Range {
    const MIN_DROP = 20;          // percent
    const MIN_METERS = 40000.0;   // 40 km
    const SAVE_EVERY_S = 60;
    const DEFAULT_KM_PER_PCT = 10.0;   // Shimano: ~1000 km per charge

    var basePct = -1;      // battery % at the last full/charged reading
    var meters = 0.0;      // distance ridden since basePct
    var kmPerPct = 0.0;    // learned, 0 = not yet (the default is used)
    var lastPct = -1;      // last battery step seen, the estimate is updated once per step
    var lastDist = -1.0;
    var dirty = false;
    var sinceSave = 0;

    function initialize() {
        try {
            var v = Application.Storage.getValue("range");
            if (v instanceof Array && v.size() == 3) {
                basePct = v[0];
                meters = v[1].toFloat();
                kmPerPct = v[2].toFloat();
            }
        } catch (e) {
        }
    }

    // Called once per second.
    // dist: Activity.Info.elapsedDistance (m) or null; timerRunning: Boolean; pct: battery or -1
    function update(dist, timerRunning, pct) {
        if (pct >= 0) {
            if (basePct < 0 || pct > basePct) {
                // first reading or battery was charged: restart the measurement
                basePct = pct;
                lastPct = pct;
                meters = 0.0;
                dirty = true;
            } else if (lastPct < 0 || pct < lastPct) {
                // the battery dropped to the next step: update the estimate once
                lastPct = pct;
                var drop = basePct - pct;
                if (drop >= MIN_DROP && meters >= MIN_METERS) {
                    var k = (meters / 1000.0) / drop;
                    // smooth with the previous (or default) estimate to avoid
                    // jumps between the coarse battery steps
                    kmPerPct = kmPerPctOrDefault() * 0.5 + k * 0.5;
                    dirty = true;
                }
            }
        }

        if (dist != null && timerRunning) {
            if (lastDist >= 0 && dist > lastDist && dist - lastDist < 500) {
                meters += dist - lastDist;
                dirty = true;
            }
            lastDist = dist;
        } else if (dist == null) {
            lastDist = -1.0;
        }

        sinceSave++;
        if (dirty && sinceSave >= SAVE_EVERY_S) {
            save();
        }
    }

    function kmPerPctOrDefault() {
        return kmPerPct > 0 ? kmPerPct : DEFAULT_KM_PER_PCT;
    }

    // Remaining range in km (default estimate until learned), -1 if the battery is unknown.
    function rangeKm(pct) {
        if (pct < 0) {
            return -1;
        }
        return pct * kmPerPctOrDefault();
    }

    function save() {
        try {
            Application.Storage.setValue("range", [basePct, meters, kmPerPct]);
        } catch (e) {
        }
        dirty = false;
        sinceSave = 0;
    }
}
