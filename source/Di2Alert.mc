import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Pop-up shown by the Edge when the Di2 battery drops below the threshold.
class Di2Alert extends WatchUi.DataFieldAlert {
    var pct;
    var rangeText;   // e.g. "48 km", or null while the range is unknown
    var title;
    var text;

    function initialize(p, r) {
        DataFieldAlert.initialize();
        pct = p;
        rangeText = r;
        title = WatchUi.loadResource(Rez.Strings.AlertTitle);
        text = WatchUi.loadResource(Rez.Strings.AlertText);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // battery icon
        var ih = (h * 0.16).toNumber();
        var iw = ih * 2;
        var x = (w - iw) / 2;
        var y = (h * 0.12).toNumber();
        dc.setPenWidth(3);
        dc.drawRoundedRectangle(x, y, iw, ih, 4);
        dc.setPenWidth(1);
        dc.fillRectangle(x + iw, y + ih / 4, 4, ih / 2);
        var fillW = ((iw - 8) * pct / 100).toNumber();
        if (fillW < 3) { fillW = 3; }
        dc.setColor(pct <= 15 ? 0xE8161A : 0xFF851B, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 4, y + 4, fillW, ih - 8);

        // percentage, remaining range (if learned), title, hint
        var cy = y + ih + (h * 0.05).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, cy, Graphics.FONT_NUMBER_HOT, pct + "%", Graphics.TEXT_JUSTIFY_CENTER);
        cy += dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        if (rangeText != null) {
            dc.drawText(w / 2, cy, Graphics.FONT_SMALL, "≈ " + rangeText, Graphics.TEXT_JUSTIFY_CENTER);
            cy += dc.getFontHeight(Graphics.FONT_SMALL);
        }
        dc.drawText(w / 2, cy, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);
        cy += dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, cy, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
