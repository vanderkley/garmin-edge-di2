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

    // the demo range is already learned: 9.5 km per % battery
    (:demo)
    function setupRange(range) {
        range.kmPerPct = 9.5;
    }

    (:nodemo)
    function setupRange(range) {
    }

    (:demo)
    function showTrial() {
        return false;
    }

    (:nodemo)
    function showTrial() {
        return true;
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

    // Per-device ride pages (chosen by screen size), each with a different split:
    // maps over 4 cells, one Di2 field over 1 or 2 cells, never the same field twice.
    // A cell is [kind, x, y, w, h] in fractions of the screen; kind is a Number
    // (Di2 field, value = view offset), :map, or a native field name.
    (:layout)
    function layoutFor(sw, sh) {
        if (sw == 480 && sh == 800) {        // Edge 1050 / 1060
            return [[:map, 0, 0, 1, 0.5], [0, 0, 0.5, 1, 0.25],
                    [:speed, 0, 0.75, 0.5, 0.25], [:heart, 0.5, 0.75, 0.5, 0.25]];
        }
        if (sw == 240 && sh == 400) {        // Edge Explore 2
            return [[:speed, 0, 0, 0.5, 0.25], [:power, 0.5, 0, 0.5, 0.25],
                    [0, 0, 0.25, 1, 0.25],
                    [:cadence, 0, 0.5, 0.5, 0.25], [:heart, 0.5, 0.5, 0.5, 0.25],
                    [:distance, 0, 0.75, 0.5, 0.25], [:time, 0.5, 0.75, 0.5, 0.25]];
        }
        if (sw == 360 && sh == 640) {        // Edge Explore 3
            return [[:map, 0, 0, 1, 0.5], [0, 0, 0.5, 0.5, 0.25], [:distance, 0.5, 0.5, 0.5, 0.25],
                    [:elevation, 0, 0.75, 0.5, 0.25], [:time, 0.5, 0.75, 0.5, 0.25]];
        }
        if (sw == 282 && sh == 470) {        // Edge 1040 / 1030
            return [[:time, 0, 0, 0.5, 0.334], [:ascent, 0.5, 0, 0.5, 0.334],
                    [0, 0, 0.334, 0.5, 0.333], [:temperature, 0.5, 0.334, 0.5, 0.333],
                    [:cadence, 0, 0.667, 0.5, 0.333], [:heart, 0.5, 0.667, 0.5, 0.333]];
        }
        if (sw == 246 && sh == 322) {        // Edge 840 / 540 / 830 / 530
            return [[:map, 0, 0, 1, 0.5], [0, 0, 0.5, 0.5, 0.5], [:calories, 0.5, 0.5, 0.5, 0.5]];
        }
        return [[:speed, 0, 0, 0.5, 0.27], [:power, 0.5, 0, 0.5, 0.27],
                [:heart, 0, 0.27, 0.5, 0.27], [:cadence, 0.5, 0.27, 0.5, 0.27], [0, 0, 0.54, 1, 0.46]];
    }

    (:layout)
    function drawPage(view, dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();
        var cells = layoutFor(w, h);
        for (var i = 0; i < cells.size(); i++) {
            var c = cells[i];
            var x = (c[1] * w).toNumber();
            var y = (c[2] * h).toNumber();
            var cw = ((c[1] + c[3]) * w).toNumber() - x;
            var ch = ((c[2] + c[4]) * h).toNumber() - y;
            var k = c[0];
            if (k instanceof Number) {
                drawDi2(view, dc, x, y, cw, ch, k);
            } else if (k == :map) {
                drawMap(dc, x, y, cw, ch);
            } else {
                var f = fieldValue(view, k);
                nativeField(dc, x, y, cw, ch, f[0], f[1], f[2]);
            }
        }
        // separators like the Edge
        dc.setColor(0x1E64C8, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(w >= 400 ? 3 : 2);
        for (var i = 0; i < cells.size(); i++) {
            var c = cells[i];
            var x = (c[1] * w).toNumber();
            var y = (c[2] * h).toNumber();
            var cw = ((c[1] + c[3]) * w).toNumber() - x;
            var ch = ((c[2] + c[4]) * h).toNumber() - y;
            if (y > 0) { dc.drawLine(x, y, x + cw, y); }
            if (x > 0) { dc.drawLine(x, y, x, y + ch); }
        }
        dc.setPenWidth(1);
    }

    // Realistic values that move with the demo gear.
    (:layout)
    function fieldValue(view, k) {
        var g = view.ble.gear;
        if (k == :speed) { return ["SPEED", (24.0 + g * 0.9 + (t % 5) * 0.1).format("%.1f"), "km/h"]; }
        if (k == :heart) { return ["HEART RATE", (128 + g + (t % 3)).toString(), "bpm"]; }
        if (k == :power) { return ["POWER", (205 + g * 6 + (t % 7)).toString(), "W"]; }
        if (k == :cadence) { return ["CADENCE", (82 + g + (t % 4)).toString(), "rpm"]; }
        if (k == :distance) { return ["DISTANCE", (42.6 + t * 0.009).format("%.1f"), "km"]; }
        if (k == :ascent) { return ["ASCENT", (412 + t / 4).toString(), "m"]; }
        if (k == :elevation) { return ["ELEVATION", (86 + (t % 20)).toString(), "m"]; }
        if (k == :temperature) { return ["TEMPERATURE", "18", "°C"]; }
        if (k == :calories) { return ["CALORIES", (640 + t * 2).toString(), "kcal"]; }
        // :time
        var s = 5072 + t;
        return ["TIME", (s / 3600) + ":" + ((s / 60) % 60).format("%02d") + ":" + (s % 60).format("%02d"), ""];
    }

    // A simple map: land, park, water, roads, the purple route and the position arrow.
    (:layout)
    function drawMap(dc, x, y, w, h) {
        dc.setClip(x, y, w, h);
        dc.setColor(0xEEF2E6, 0xEEF2E6);
        dc.fillRectangle(x, y, w, h);
        dc.setColor(0xCDE6C0, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x + w * 0.62, y], [x + w, y], [x + w, y + h * 0.42], [x + w * 0.7, y + h * 0.35]]);
        dc.setColor(0xAED3F2, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y + h * 0.7], [x + w * 0.22, y + h * 0.62], [x + w * 0.3, y + h], [x, y + h]]);
        // roads
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((w * 0.035).toNumber());
        dc.drawLine(x, y + h * 0.3, x + w, y + h * 0.18);
        dc.drawLine(x + w * 0.35, y, x + w * 0.5, y + h);
        dc.setPenWidth((w * 0.018).toNumber());
        dc.drawLine(x + w * 0.5, y + h * 0.55, x + w, y + h * 0.75);
        dc.drawLine(x + w * 0.1, y + h * 0.45, x + w * 0.4, y + h * 0.5);
        // route
        dc.setColor(0x7B2FF7, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((w * 0.022).toNumber());
        var r = [[0.05, 0.95], [0.25, 0.78], [0.45, 0.62], [0.5, 0.45], [0.72, 0.3], [0.95, 0.24]];
        for (var i = 0; i < r.size() - 1; i++) {
            dc.drawLine(x + w * r[i][0], y + h * r[i][1], x + w * r[i + 1][0], y + h * r[i + 1][1]);
        }
        dc.setPenWidth(1);
        // position arrow
        var ax = x + w * 0.45;
        var ay = y + h * 0.62;
        var s = w * 0.05;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[ax, ay - s * 1.4], [ax + s * 1.0, ay + s * 1.1], [ax, ay + s * 0.5], [ax - s * 1.0, ay + s * 1.1]]);
        dc.setColor(0x1E64C8, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[ax, ay - s], [ax + s * 0.7, ay + s * 0.8], [ax, ay + s * 0.35], [ax - s * 0.7, ay + s * 0.8]]);
        dc.clearClip();
    }

    (:layout)
    function drawDi2(view, dc, x, y, w, h, offset) {
        var ref = Graphics.createBufferedBitmap({ :width => w, :height => h });
        var bmp = ref.get();
        var m = view.mode;
        view.mode = (m + offset) % Di2View.MODE_COUNT;
        view.drawField(bmp.getDc());
        view.mode = m;
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
