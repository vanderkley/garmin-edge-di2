import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.StringUtil;

// Pro license codes: XXXX-XXXX = first 40 bits of SHA-256(secret + "|" + email),
// written in an unambiguous base-32 alphabet. Checked offline on the device.
module Di2License {
    const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    function normalizeEmail(email) {
        if (email == null) {
            return "";
        }
        return trim(email.toString()).toLower();
    }

    function normalizeCode(code) {
        if (code == null) {
            return "";
        }
        var s = code.toString().toUpper();
        var out = "";
        for (var i = 0; i < s.length(); i++) {
            var c = s.substring(i, i + 1);
            if (!c.equals("-") && !c.equals(" ")) {
                out += c;
            }
        }
        return out;
    }

    function codeFor(email) {
        var bytes = StringUtil.convertEncodedString(Di2Secret.SECRET + "|" + normalizeEmail(email), {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
        var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
        hash.update(bytes);
        var d = hash.digest();
        var v = 0l;
        for (var i = 0; i < 5; i++) {
            v = (v << 8) | (d[i] & 0xFF).toLong();
        }
        var out = "";
        for (var i = 7; i >= 0; i--) {
            var idx = ((v >> (i * 5)) & 0x1Fl).toNumber();
            out += ALPHABET.substring(idx, idx + 1);
        }
        return out;
    }

    function isValid(email, code) {
        var e = normalizeEmail(email);
        var c = normalizeCode(code);
        if (e.length() < 3 || c.length() != 8) {
            return false;
        }
        return codeFor(e).equals(c);
    }

    function trim(s) {
        var a = 0;
        var b = s.length();
        while (a < b && s.substring(a, a + 1).equals(" ")) { a++; }
        while (b > a && s.substring(b - 1, b).equals(" ")) { b--; }
        return s.substring(a, b);
    }
}
