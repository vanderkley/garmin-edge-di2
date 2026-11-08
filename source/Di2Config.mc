import Toybox.Application;
import Toybox.Lang;

// User configuration (set in the Connect IQ app / Garmin Connect settings).
// Cassettes are listed largest cog first: gear 1 = largest cog (verified on RD-M8250).
class Di2Config {
    static const CASSETTES = [
        null,                                              // 0 not set
        [51, 45, 39, 33, 28, 24, 21, 18, 16, 14, 12, 10],  // 1 10-51 12s
        [45, 40, 36, 32, 28, 24, 21, 18, 16, 14, 12, 10],  // 2 10-45 12s
        [50, 44, 40, 36, 32, 28, 24, 21, 18, 15, 13, 11],  // 3 11-50 Linkglide
        [30, 27, 24, 21, 19, 17, 16, 15, 14, 13, 12, 11],  // 4 11-30 12s road
        [34, 30, 27, 24, 21, 19, 17, 15, 14, 13, 12, 11],  // 5 11-34 12s road
        [36, 32, 28, 24, 21, 19, 17, 15, 14, 13, 12, 11],  // 6 11-36 12s road
        [28, 25, 23, 21, 19, 17, 15, 14, 13, 12, 11],      // 7 11-28 11s
        [32, 28, 25, 22, 20, 18, 16, 14, 13, 12, 11],      // 8 11-32 11s
        [34, 30, 27, 25, 23, 21, 19, 17, 15, 13, 11]       // 9 11-34 11s
    ];
    static const CUSTOM = 10;

    var cogs = null;        // Array<Number> or null
    var rings = [];         // chainrings, largest first
    var battWarn = 10;

    function initialize() {
        load();
    }

    var bike = 1;           // active bike profile (1 or 2)
    var licensed = false;   // valid Pro license code entered

    function load() {
        licensed = Di2License.isValid(readString("licenseEmail"), readString("licenseKey"));
        // the second bike profile needs Pro (or the trial)
        bike = ((licensed || Di2Pro.trialActive()) && readNumber("bike", 1) == 2) ? 2 : 1;
        var suf = bike == 2 ? "2" : "";
        var c = readNumber("cassette" + suf, 0);
        if (c == CUSTOM) {
            cogs = parseList(readString("customCogs" + suf));
            if (cogs.size() < 2) {
                cogs = null;
            }
        } else if (c > 0 && c < CASSETTES.size()) {
            cogs = CASSETTES[c];
        } else {
            cogs = null;
        }
        rings = parseList(readString("chainrings" + suf));
        battWarn = readNumber("battWarn", 10);
    }

    // Cog teeth for a rear gear, or 0 if unknown / cassette does not match.
    function teeth(gear, gearCount) {
        if (cogs == null || cogs.size() != gearCount || gear < 1 || gear > cogs.size()) {
            return 0;
        }
        return cogs[gear - 1];
    }

    // Chainring teeth for a front gear (1 = smallest ring, like Shimano), or 0.
    function ring(front, frontCount) {
        if (rings.size() == 0) {
            return 0;
        }
        if (rings.size() == 1) {
            return rings[0];
        }
        if (front < 1 || front > rings.size()) {
            return 0;
        }
        // rings are entered largest first; front 1 = small ring
        return rings[rings.size() - front];
    }

    hidden function readNumber(key, def) {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Number) {
                return v;
            }
            if (v instanceof String) {
                var n = v.toNumber();
                return n == null ? def : n;
            }
        } catch (e) {
        }
        return def;
    }

    hidden function readString(key) {
        try {
            var v = Application.Properties.getValue(key);
            if (v != null) {
                return v.toString();
            }
        } catch (e) {
        }
        return "";
    }

    // "50, 34" -> [50, 34]  (ignores anything that is not a number 5..99)
    static function parseList(s) {
        var out = [];
        var cur = "";
        s = s + ",";
        for (var i = 0; i < s.length(); i++) {
            var ch = s.substring(i, i + 1);
            if (ch.equals(",") || ch.equals(" ") || ch.equals(";") || ch.equals("-") || ch.equals("/")) {
                if (cur.length() > 0) {
                    var n = cur.toNumber();
                    if (n != null && n >= 5 && n <= 99) {
                        out.add(n);
                    }
                    cur = "";
                }
            } else {
                cur += ch;
            }
        }
        return out;
    }
}
