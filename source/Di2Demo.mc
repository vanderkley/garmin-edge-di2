import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

// Demo data for the simulator, selected by the jungle file:
//   monkey.jungle   release (no demo code)
//   demo.jungle     fake data, one full-screen field
//   layouts.jungle  fake data, a full Edge page with several fields
//   lowbatt.jungle  fake data with an 8% battery and a running timer
//                   (shows the low-battery tone and red label)
//   trialend.jungle page demo with the 500 km trial used up (lock screen)
module Di2Demo {
    var t = 0;

    (:demo)
    function start(ble) {
        ble.state = Di2Ble.ST_READY;
        ble.gear = 6;
        ble.gearCount = 12;
        ble.battery = demoBattery();
    }

    // called once per second: walk through the gears, switch view every 6 s,
    // and show the "searching" screen for 6 s after every full cycle
    (:demo)
    function tick(ble) {
        t++;
        ble.gear = 1 + (t % 36) / 3;   // all 12 gears once per 36 s cycle
        var phase = (t / 6) % 6;
        ble.state = (phase == 5) ? Di2Ble.ST_SCAN : Di2Ble.ST_READY;
        if (t % 6 == 0 && phase != 0) {
            ble.dflyEvents.add(:short);
        }
    }

    (:nodemo)
    function start(ble) {
        ble.start();
    }

    (:nodemo)
    function tick(ble) {
    }

    (:normalbatt)
    function demoBattery() {
        return 80;
    }

    (:normalbatt)
    function forceRunning() {
        return false;
    }

    (:lowbatt)
    function demoBattery() {
        return 8;
    }

    (:lowbatt)
    function forceRunning() {
        return true;
    }

    // trialend.jungle: pretend the 500 km trial is used up (shows the lock screen)
    (:normaltrial)
    function trialMeters(m) {
        return m;
    }

    (:trialend)
    function trialMeters(m) {
        return 600000.0;
    }

    (:single)
    function isLayoutDemo() {
        return false;
    }

    (:single)
    function drawPage(view, dc) {
    }

    (:layout)
    function isLayoutDemo() {
        return true;
    }

    // A realistic ride page around two Di2 fields (any screen size):
    //   [ Di2 half ][  SPEED  ]
    //   [  POWER   ][  HEART  ]
    //   [   Di2 full width    ]
    (:layout)
    function drawPage(view, dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var row1 = (h * 0.27).toNumber();
        var row2 = (h * 0.27).toNumber();
        var row3 = h - row1 - row2;
        var half = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        // values follow the demo gear a little, like a real ride
        var g = view.ble.gear;
        var speed = 24.0 + g * 0.9 + (t % 5) * 0.1;
        var power = 205 + g * 6 + (t % 7);
        var hr = 128 + g + (t % 3);

        drawDi2(view, dc, 0, 0, half, row1);
        nativeField(dc, half, 0, w - half, row1, "SPEED", speed.format("%.1f"), "km/h");
        nativeField(dc, 0, row1, half, row2, "POWER", power.toString(), "W");
        nativeField(dc, half, row1, w - half, row2, "HEART RATE", hr.toString(), "bpm");
        drawDi2(view, dc, 0, row1 + row2, w, row3);

        // separators like the Edge
        var pw = w >= 400 ? 3 : 2;
        dc.setColor(0x1E64C8, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pw);
        dc.drawLine(0, row1, w, row1);
        dc.drawLine(0, row1 + row2, w, row1 + row2);
        dc.drawLine(half, 0, half, row1 + row2);
        dc.setPenWidth(1);
    }

    (:layout)
    function drawDi2(view, dc, x, y, w, h) {
        var ref = Graphics.createBufferedBitmap({ :width => w, :height => h });
        var bmp = ref.get();
        view.drawField(bmp.getDc());
        dc.drawBitmap(x, y, bmp);
    }

    // Static stand-in for a native Edge field (label + big value + small unit).
    (:layout)
    function nativeField(dc, x, y, w, h, label, value, unit) {
        var sw = System.getDeviceSettings().screenWidth;
        var lf = (w >= sw * 0.8) ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL;
        var pad = (h * 0.05).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, y + pad, lf, label, Graphics.TEXT_JUSTIFY_CENTER);
        var top = y + pad + dc.getFontHeight(lf);
        var uw = dc.getTextWidthInPixels(unit, Graphics.FONT_SMALL);
        // largest number font that fits the field, like the Edge does
        var fonts = [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD];
        var vf = Graphics.FONT_NUMBER_MILD;
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(value, fonts[i]) + uw + 10 <= w
                && dc.getFontAscent(fonts[i]) - dc.getFontDescent(fonts[i]) <= h - (top - y)) {
                vf = fonts[i];
                break;
            }
        }
        var vw = dc.getTextWidthInPixels(value, vf);
        var vx = x + (w - vw - uw - 2) / 2;
        var cy = top + (y + h - top) / 2;
        dc.drawText(vx, cy, vf, value, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(vx + vw + 2, cy, Graphics.FONT_SMALL, unit, Graphics.TEXT_JUSTIFY_LEFT);
    }
}
