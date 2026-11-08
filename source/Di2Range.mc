import Toybox.Application;
import Toybox.Lang;

// Learns how far THIS bike rides per percent of Di2 battery and estimates the
// remaining range. Nothing is shown until enough data was collected, because
// Di2 consumption depends on the number of shifts, not on distance.
//
// Shimano reports the battery in coarse steps (100, 90, 80 ... 25, 20, 15, 10, 5, 0),
// so we need at least MIN_DROP percent and MIN_KM since the last charge.
class Di2Range {
    const MIN_DROP = 20;          // percent
    const MIN_METERS = 40000.0;   // 40 km
    const SAVE_EVERY_S = 60;

    var basePct = -1;      // battery % at the last full/charged reading
    var meters = 0.0;      // distance ridden since basePct
    var kmPerPct = 0.0;    // learned, 0 = unknown
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
                meters = 0.0;
                dirty = true;
            } else {
                var drop = basePct - pct;
                if (drop >= MIN_DROP && meters >= MIN_METERS) {
                    var k = (meters / 1000.0) / drop;
                    // smooth with the previous estimate to avoid jumps between 10% steps
                    kmPerPct = (kmPerPct > 0) ? (kmPerPct * 0.5 + k * 0.5) : k;
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

    // Remaining range in km, or -1 if not learned yet.
    function rangeKm(pct) {
        if (kmPerPct <= 0 || pct < 0) {
            return -1;
        }
        return pct * kmPerPct;
    }

    // Learning progress for the display: [done, target, unit] where unit is
    // "km" while distance is still missing, otherwise "%" battery used.
    function progress(pct) {
        if (meters < MIN_METERS) {
            return [(meters / 1000.0).toNumber(), (MIN_METERS / 1000.0).toNumber(), "km"];
        }
        var drop = (basePct >= 0 && pct >= 0) ? basePct - pct : 0;
        return [drop, MIN_DROP, "%"];
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
