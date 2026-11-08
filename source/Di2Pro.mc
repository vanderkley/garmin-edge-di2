import Toybox.Application;
import Toybox.Lang;

// Free trial: the whole field works for the first TRIAL_METERS ridden with the
// Di2 connected and the timer running. After that a license code is needed.
const TRIAL_METERS = 500000.0;   // 500 km

class Di2Pro {

    var licensed = false;
    var trialMeters = 0.0;
    var lastDist = -1.0;
    var sinceSave = 0;

    function initialize() {
        try {
            var v = Application.Storage.getValue("trial");
            if (v != null) {
                trialMeters = v.toFloat();
            }
        } catch (e) {
        }
    }

    // Field usable (bought, or still in the trial)
    function unlocked() {
        return licensed || Di2Demo.trialMeters(trialMeters) < TRIAL_METERS;
    }

    // Trial kilometres left (0 when ended)
    function remainingKm() {
        var m = TRIAL_METERS - Di2Demo.trialMeters(trialMeters);
        return m > 0 ? m / 1000.0 : 0.0;
    }

    // Used by Di2Config before the view exists.
    static function trialActive() {
        try {
            var v = Application.Storage.getValue("trial");
            return v == null || v.toFloat() < TRIAL_METERS;
        } catch (e) {
            return true;
        }
    }

    // Called once per second while the Di2 is connected.
    function update(dist, running) {
        if (licensed) {
            return;
        }
        if (dist != null && running) {
            if (lastDist >= 0 && dist > lastDist && dist - lastDist < 500) {
                trialMeters += dist - lastDist;
            }
            lastDist = dist;
        } else {
            lastDist = -1.0;
        }
        sinceSave++;
        if (sinceSave >= 60) {
            save();
        }
    }

    function save() {
        sinceSave = 0;
        try {
            Application.Storage.setValue("trial", trialMeters);
        } catch (e) {
        }
    }
}
