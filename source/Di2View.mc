import Toybox.Activity;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Layout follows the native Edge data fields: centred label on top,
// large number below, unit small and raised next to it, plus a cassette
// graphic (bar height = cog size) and a small battery badge.
class Di2View extends WatchUi.DataField {
    enum { MODE_GEAR, MODE_COG, MODE_RATIO, MODE_BATT, MODE_RANGE, MODE_COUNT }

    var ble;
    var cfg;
    var range;
    var pro;
    var sTrialEnded;
    var sUnlock;
    var sTrialLeft;
    var trialShowUntil = 0;     // ticks: show the trial km in the label until then
    var wasConnected = false;
    var wasRunning = false;
    const KOFI = "ko-fi.com/vanderkley";
    var mode = MODE_GEAR;
    var flashUntil = 0;
    var ticks = 0;
    var labels = [];
    var labelsShort = [];
    var sConnecting;
    var sWake;
    var sFw1;
    var sFw2;
    var sFwShort1;
    var sFwShort2;
    var metric = true;
    var sw = 240;    // screen size, layout rules are relative to it
    var sh = 400;

    var stale = false;
    var alerted = false;
    var runningTicks = 0;   // seconds the timer has been running
    const COLOR_STALE = 0x9A9A9A;

    var fitGear = null;
    var fitTeeth = null;
    var fitBatt = null;
    var fitRatio = null;
    var fitAvgRatio = null;
    var fitMaxRatio = null;
    var fitShifts = null;
    var fitGearPct = [];     // session: % of ride time per gear (gear 1..12)

    // ride statistics (only while the timer runs)
    var gearSecs = new [13];
    var rideSecs = 0;
    var ratioSum = 0.0;
    var ratioN = 0;
    var ratioMax = 0.0;
    var shifts = 0;
    var lastGear = 0;

    // Shimano battery colour scale: 100-40 green, 30-20 orange, 15-0 red
    const COLOR_OK = 0x2ECC40;
    const COLOR_MID = 0xFF851B;
    const COLOR_LOW = 0xE8161A;
    const COLOR_ACCENT = 0xFF6A00;

    function initialize(b, c) {
        DataField.initialize();
        ble = b;
        cfg = c;
        range = new Di2Range();
        Di2Demo.setupRange(range);
        pro = new Di2Pro();
        pro.licensed = cfg.licensed;
        labels = [
            WatchUi.loadResource(Rez.Strings.ModeGear),
            WatchUi.loadResource(Rez.Strings.ModeCog),
            WatchUi.loadResource(Rez.Strings.ModeRatio),
            WatchUi.loadResource(Rez.Strings.ModeBattery),
            WatchUi.loadResource(Rez.Strings.ModeRange)
        ];
        // only "BATTERY RANGE" gets a shorter label in narrow fields
        labelsShort = [labels[0], labels[1], labels[2], labels[3],
            WatchUi.loadResource(Rez.Strings.ModeRangeShort)];
        sConnecting = WatchUi.loadResource(Rez.Strings.Connecting);
        sWake = WatchUi.loadResource(Rez.Strings.WakeHint);
        sFw1 = WatchUi.loadResource(Rez.Strings.FwUnsupported1);
        sFw2 = WatchUi.loadResource(Rez.Strings.FwUnsupported2);
        sTrialEnded = WatchUi.loadResource(Rez.Strings.TrialEnded);
        sUnlock = WatchUi.loadResource(Rez.Strings.UnlockHint);
        sTrialLeft = WatchUi.loadResource(Rez.Strings.TrialLeft);
        sFwShort1 = WatchUi.loadResource(Rez.Strings.FwShort1);
        sFwShort2 = WatchUi.loadResource(Rez.Strings.FwShort2);
        var ds = System.getDeviceSettings();
        metric = ds.distanceUnits == System.UNIT_METRIC;
        sw = ds.screenWidth;
        sh = ds.screenHeight;
        try {
            fitGear = createField("gear", 0, FitContributor.DATA_TYPE_UINT8,
                { :mesgType => FitContributor.MESG_TYPE_RECORD });
            fitTeeth = createField("cog_teeth", 1, FitContributor.DATA_TYPE_UINT8,
                { :mesgType => FitContributor.MESG_TYPE_RECORD });
            fitBatt = createField("di2_battery", 2, FitContributor.DATA_TYPE_UINT8,
                { :mesgType => FitContributor.MESG_TYPE_SESSION });
            fitRatio = createField("gear_ratio", 3, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD });
            fitAvgRatio = createField("avg_gear_ratio", 4, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION });
            fitMaxRatio = createField("max_gear_ratio", 5, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION });
            fitShifts = createField("shifts", 6, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_SESSION });
            for (var i = 1; i <= 12; i++) {
                fitGearPct.add(createField("gear" + i + "_pct", 9 + i, FitContributor.DATA_TYPE_UINT8,
                    { :mesgType => FitContributor.MESG_TYPE_SESSION }));
            }
        } catch (e) {
            fitGear = null;
        }
        for (var i = 0; i < 13; i++) {
            gearSecs[i] = 0;
        }
    }

    function onStop() {
        range.save();
        pro.save();
    }

    // A mode is only offered when its data can be shown.
    // Battery-only mode (Edge firmware blocks the gear service): battery and range.
    function modeAvailable(m) {
        if (!ble.gearAvailable) {
            return m == MODE_BATT || m == MODE_RANGE;
        }
        if (m == MODE_COG) {
            return cfg.cogs != null;
        }
        if (m == MODE_RATIO) {
            return cfg.cogs != null && cfg.rings.size() > 0;
        }
        return true;
    }

    function stepMode(dir) {
        for (var i = 0; i < MODE_COUNT; i++) {
            mode = (mode + dir + MODE_COUNT) % MODE_COUNT;
            if (modeAvailable(mode)) {
                return;
            }
        }
        mode = defaultMode();
    }

    function defaultMode() {
        return ble.gearAvailable ? MODE_GEAR : MODE_BATT;
    }

    // ---------- once per second ----------
    function compute(info as Activity.Info) as Void {
        ticks++;
        if (ble == null) {
            return;
        }
        ble.tick();
        Di2Demo.tick(ble);

        var events = ble.takeEvents();
        for (var i = 0; i < events.size(); i++) {
            var e = events[i];
            if (e == :short) {
                stepMode(1);
            } else if (e == :long) {
                stepMode(-1);
            } else if (e == :double) {
                mode = defaultMode();
            }
            flashUntil = ticks + 2;
        }
        if (!modeAvailable(mode)) {
            mode = defaultMode();
        }

        var running = info has :timerState && info.timerState == Activity.TIMER_STATE_ON;
        running = running || Di2Demo.forceRunning();
        // show the remaining trial km for 5 s when the Di2 connects or the ride starts
        var conn = ble.isConnected();
        if ((conn && !wasConnected) || (running && !wasRunning)) {
            trialShowUntil = ticks + 5;
        }
        wasConnected = conn;
        wasRunning = running;
        if (pro.unlocked()) {
            checkBatteryAlert(running);
        }
        pro.licensed = cfg.licensed;    // settings may have changed
        if (ble.isConnected()) {
            pro.update(info has :elapsedDistance ? info.elapsedDistance : null, running);
        }
        range.update(info has :elapsedDistance ? info.elapsedDistance : null, running, ble.battery);

        updateStats(running);
        if (fitBatt != null && ble.battery >= 0) {
            fitBatt.setData(ble.battery);
        }
    }

    // Gear usage, ratio and shift statistics for Garmin Connect.
    function updateStats(running) {
        var g = ble.gear;
        // FIT stats are a Pro feature (free during the trial)
        if (fitGear == null || g <= 0 || !ble.isConnected() || !pro.unlocked()) {
            return;
        }
        var t = cfg.teeth(g, ble.gearCount);
        var r = cfg.ring(ble.front, ble.frontCount);
        var ratio = (t > 0 && r > 0) ? r.toFloat() / t : 0.0;

        fitGear.setData(g);
        if (t > 0) {
            fitTeeth.setData(t);
        }
        if (ratio > 0) {
            fitRatio.setData(ratio);
        }
        if (!running) {
            lastGear = g;
            return;
        }

        if (lastGear > 0 && g != lastGear) {
            shifts++;
        }
        lastGear = g;
        if (g <= 12) {
            gearSecs[g]++;
        }
        rideSecs++;
        if (ratio > 0) {
            ratioSum += ratio;
            ratioN++;
            if (ratio > ratioMax) {
                ratioMax = ratio;
            }
        }

        fitShifts.setData(shifts);
        if (ratioN > 0) {
            fitAvgRatio.setData(ratioSum / ratioN);
            fitMaxRatio.setData(ratioMax);
        }
        // percentages every 10 s is plenty
        if (rideSecs % 10 == 1) {
            var n = ble.gearCount < 12 ? ble.gearCount : 12;
            for (var i = 1; i <= n; i++) {
                fitGearPct[i - 1].setData((gearSecs[i] * 100 + rideSecs / 2) / rideSecs);
            }
        }
    }

    // Once per ride when the battery reaches the threshold (default 10%):
    // a warning tone, plus a pop-up where the Edge allows Connect IQ alerts.
    // The field label stays red while the battery is low.
    // Reset after the battery was charged above the threshold.
    function checkBatteryAlert(running) {
        var p = ble.battery;
        if (p < 0) {
            return;
        }
        if (p > cfg.battWarn) {
            alerted = false;
            return;
        }
        // wait 10 s after the timer starts so the Edge's own
        // "timer started" message does not hide the pop-up
        runningTicks = running ? runningTicks + 1 : 0;
        if (alerted || runningTicks < 10) {
            return;
        }
        alerted = true;
        var km = range.rangeKm(p);
        var rangeText = null;
        if (km >= 0) {
            var v = metric ? km : km / 1.609344;
            rangeText = v.toNumber() + (metric ? " km" : " mi");
        }
        try {
            showAlert(new Di2Alert(p, rangeText));
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_ALERT_HI);
            }
            System.println(System.getTimer() + " alert shown " + p + "%");
        } catch (e) {
            System.println(System.getTimer() + " alert failed " + e.getErrorMessage());
        }
    }

    // ---------- value for the current mode: [text, unit] ----------
    function currentValue() {
        var g = ble.gear;
        if (mode == MODE_GEAR) {
            if (g <= 0) { return ["--", ""]; }
            if (ble.front > 0) {
                return [ble.front + "-" + g, ""];
            }
            return [g.toString(), "/" + ble.gearCount];
        }
        if (mode == MODE_COG) {
            var t = cfg.teeth(g, ble.gearCount);
            return t > 0 ? [t.toString(), "T"] : ["--", ""];
        }
        if (mode == MODE_RATIO) {
            var t = cfg.teeth(g, ble.gearCount);
            var r = cfg.ring(ble.front, ble.frontCount);
            if (t > 0 && r > 0) {
                return [(r.toFloat() / t).format("%.2f"), ""];
            }
            return ["--", ""];
        }
        if (mode == MODE_BATT) {
            return ble.battery >= 0 ? [ble.battery.toString(), "%"] : ["--", ""];
        }
        // MODE_RANGE
        var km = range.rangeKm(ble.battery);
        if (km < 0) {
            return ["--", ""];
        }
        var v = metric ? km : km / 1.609344;
        return [v.toNumber().toString(), metric ? "km" : "mi"];
    }

    function battColor(p) {
        if (p >= 40) { return COLOR_OK; }
        if (p >= 20 && p >= cfg.battWarn) { return COLOR_MID; }
        return COLOR_LOW;
    }

    // ---------- drawing ----------
    // Label size follows the native Edge fields: big fields get the large label.
    function labelFontFor(w, h) {
        if (h < sh * 0.15) { return Graphics.FONT_XTINY; }
        if (isWide(w) && h >= sh * 0.27) { return Graphics.FONT_MEDIUM; }
        if (h >= sh * 0.19) { return Graphics.FONT_SMALL; }
        return Graphics.FONT_TINY;
    }

    // full-width field (as opposed to a half-width one)
    function isWide(w) {
        return w >= sw * 0.8;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // the "layouts" demo build draws a whole multi-field page itself
        if (Di2Demo.isLayoutDemo()) {
            Di2Demo.drawPage(self, dc);
            return;
        }
        drawField(dc);
    }

    // Draws the field into dc (also used for off-screen bitmaps by the demo).
    function drawField(dc) {
        var bg = getBackgroundColor();
        var dark = (bg == Graphics.COLOR_BLACK);
        var fg = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();
        if (ble == null) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var label = isWide(w) ? labels[mode] : labelsShort[mode];
        var trialLabel = false;
        if (Di2Demo.showTrial() && !pro.licensed && pro.unlocked() && ble.isConnected()) {
            var left = pro.remainingKm();
            if (left <= 5 || ticks < trialShowUntil) {
                var v = metric ? left : left / 1.609344;
                label = Lang.format(sTrialLeft, [v.toNumber() + (metric ? " km" : " mi")]);
                trialLabel = true;
            }
        }
        var labelFont = fitFont(dc, label, labelFontFor(w, h),
            [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY], w - 6);
        // top padding like the native fields: a fixed margin relative to the
        // screen (about 8 px on a 400 px high screen), less only in very low fields
        var pad = (sh * 0.02).toNumber();
        if (pad > h * 0.12) { pad = (h * 0.12).toNumber(); }
        if (pad < 2) { pad = 2; }
        var lh = pad + dc.getFontHeight(labelFont);

        stale = ble.isStale();
        var connected = ble.isConnected() || stale;

        // cassette (and chainrings on 2x) as background graphic
        if (connected && ble.gear > 0 && h >= 50) {
            if (mode == MODE_COG && cfg.rings.size() > 0 && cfg.teeth(ble.gear, ble.gearCount) > 0) {
                drawDrivetrain(dc, dark, bg, 3, lh + 2, w - 6, h - lh - 4);
            } else {
                drawGearBackground(dc, dark, 3, lh + 2, w - 6, h - lh - 4);
            }
        }

        // label
        // label: orange right after a D-FLY switch, red while the Di2 battery is low
        var labelColor = fg;
        if (ticks < flashUntil || trialLabel) {
            labelColor = COLOR_ACCENT;
        } else if (connected && ble.battery >= 0 && ble.battery <= cfg.battWarn) {
            labelColor = COLOR_LOW;
        }
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, pad, labelFont, label, Graphics.TEXT_JUSTIFY_CENTER);

        // battery badge (top right) when not showing the battery itself,
        // only if it does not collide with the centred label
        if (connected && ble.battery >= 0 && mode != MODE_BATT) {
            var fh = lh - pad;
            var ih = (fh * 0.62).toNumber();
            if (ih < 8) { ih = 8; }
            var iconW = ih * 2 + 4;
            var labelW = dc.getTextWidthInPixels(label, labelFont);
            if ((w - labelW) / 2 >= iconW + 8) {
                drawBattery(dc, fg, w - 5, pad + (fh - ih) / 2, ih, ble.battery);
            }
        }

        if (ble.state == Di2Ble.ST_FW_UNSUPPORTED) {
            drawHint(dc, fg, lh, labelFont, sFw1, sFw2, sFwShort1, sFwShort2);
            return;
        }
        // trial over and no license: the whole field is locked
        if (!pro.unlocked()) {
            drawLocked(dc, fg, lh, labelFont, w, h);
            return;
        }
        // not connected yet: ask to wake the Di2; once it is found: "Connecting Di2…"
        if (!stale && ble.isConnecting()) {
            drawMessage(dc, fg, lh, labelFont, sConnecting);
            return;
        }
        if (!connected) {
            drawMessage(dc, fg, lh, labelFont, sWake);
            return;
        }

        var val = currentValue();
        var unitFont = labelFont;
        if (val[1].length() > 3 && !isWide(w)) { unitFont = Graphics.FONT_XTINY; }
        var bottom = h - 2;
        // battery-only mode (no D-FLY to switch views): range below the battery %
        if (!ble.gearAvailable && mode == MODE_BATT) {
            var km = range.rangeKm(ble.battery);
            var secH = dc.getFontHeight(labelFont);
            if (km >= 0 && h - lh >= secH * 3) {
                var v = metric ? km : km / 1.609344;
                var txt = v.toNumber() + (metric ? " km" : " mi");
                bottom = h - 2 - secH;
                dc.setColor(valueColor(), Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, bottom, labelFont, txt, Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
        drawValue(dc, fg, val[0], val[1], unitFont, lh, bottom, w);
    }

    function drawValue(dc, fg, text, unit, unitFont, top, bottom, w) {
        var avail = bottom - top;
        var unitW = unit.length() > 0 ? dc.getTextWidthInPixels(unit, unitFont) + 3 : 0;
        var fonts = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
                     Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD,
                     Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL];
        var font = Graphics.FONT_SMALL;
        for (var i = 0; i < fonts.size(); i++) {
            // digits only use the ascent part of a number font
            var glyphH = dc.getFontAscent(fonts[i]) - dc.getFontDescent(fonts[i]);
            if (glyphH <= avail && dc.getTextWidthInPixels(text, fonts[i]) + unitW <= w - 6) {
                font = fonts[i];
                break;
            }
        }
        var tw = dc.getTextWidthInPixels(text, font);
        var x = (w - tw - unitW) / 2;
        var cy = top + avail / 2;
        dc.setColor(valueColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (unitW > 0) {
            // raised unit, like the native "00" seconds / units
            var glyph = dc.getFontAscent(font) - dc.getFontDescent(font);
            var uy = cy - glyph / 2;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + tw + 3, uy, unitFont, unit, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function valueColor() {
        if (stale) {
            return COLOR_STALE;
        }
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        if ((mode == MODE_BATT || mode == MODE_RANGE) && ble.battery >= 0 && ble.battery < cfg.battWarn) {
            return COLOR_LOW;
        }
        return fg;
    }

    // Background graphic: one bar per cog, bottom-aligned, filling the field.
    // Heights are stretched between 12% (smallest cog) and 100% (largest cog)
    // so the difference is clearly visible; the active cog is orange.
    // On 2x/3x systems the chainrings are drawn on the left in the same style.
    function drawGearBackground(dc, dark, x, y, gw, gh) {
        var n = ble.gearCount;
        if (n < 1 || gw < 20 || gh < 10) {
            return;
        }
        var idle = dark ? 0x2E2E2E : 0xDCDCDC;
        var cogs = (cfg.cogs != null && cfg.cogs.size() == n) ? cfg.cogs : null;

        // chainrings
        var fc = ble.frontCount;
        var unit = gw / (n + (fc >= 2 ? fc + 1 : 0));
        var gap = unit >= 8 ? 2 : 1;
        var bw = unit - gap;
        if (bw < 2) { bw = 2; }
        var cx = x + (gw - unit * (n + (fc >= 2 ? fc + 1 : 0)) + gap) / 2;
        if (fc >= 2) {
            for (var r = 1; r <= fc; r++) {
                // ring 1 = small ring: lower bar
                var rh = (gh * (0.6 + 0.4 * (r - 1) / (fc - 1))).toNumber();
                dc.setColor(r == ble.front ? accent() : idle, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx, y + gh - rh, bw, rh);
                cx += unit;
            }
            cx += unit; // spacer between rings and cassette
        }

        // cassette, gear 1 (largest cog) on the left
        var maxT = cogs != null ? cogs[0] : n;
        var minT = cogs != null ? cogs[n - 1] : 1;
        var span = maxT - minT;
        if (span <= 0) { span = 1; }
        for (var i = 1; i <= n; i++) {
            var t = cogs != null ? cogs[i - 1] : (n - i + 1);
            var frac = 0.12 + 0.88 * (t - minT).toFloat() / span;
            var bh = (gh * frac).toNumber();
            dc.setColor(i == ble.gear ? accent() : idle, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx, y + gh - bh, bw, bh);
            cx += unit;
        }
    }

    // Battery icon right-aligned at (xr, y), height ih, with percent text left of it.
    function drawBattery(dc, fg, xr, y, ih, pct) {
        if (ih < 8) { ih = 8; }
        var iw = ih * 2;
        var x = xr - iw - 2;
        var b = ih >= 16 ? 2 : 1;   // frame thickness
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(b);
        dc.drawRoundedRectangle(x, y, iw, ih, 2);
        dc.setPenWidth(1);
        dc.fillRectangle(x + iw, y + ih / 4, b + 1, ih / 2);
        var inner = iw - 2 * (b + 1);
        var fillW = (inner * pct / 100).toNumber();
        if (fillW < 1 && pct > 0) { fillW = 1; }
        dc.setColor(battColor(pct), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + b + 1, y + b + 1, fillW, ih - 2 * (b + 1));
    }

    // Two centred lines; line 1 uses the label font (like the native labels),
    // both shrink when they do not fit the field width.
    // Small fields only get the short text, big fields both lines.
    function drawHint(dc, fg, top, labelFont, line1, line2, short1, short2) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (!isWide(w) || h < sh * 0.22) {
            line1 = short1;
            line2 = short2;
        }
        if (line2.length() == 0) {
            var order1 = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
            var fs = fitFont(dc, line1, labelFont, order1, w - 6);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, top + (h - top) / 2, fs, line1,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var order = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        var f1 = fitFont(dc, line1, labelFont, order, w - 6);
        var f2 = fitFont(dc, line2, smaller(f1, order), order, w - 6);
        var total = dc.getFontHeight(f1) + dc.getFontHeight(f2);
        var y = top + (h - top - total) / 2;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, f1, line1, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, y + dc.getFontHeight(f1), f2, line2, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // "Trial ended / Unlock Pro: / ko-fi.com/vanderkley", centred, fitted to the field.
    function drawLocked(dc, fg, top, labelFont, w, h) {
        var order = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        var lines = isWide(w) && h >= sh * 0.22 ? [sTrialEnded, sUnlock, KOFI] : [sTrialEnded, KOFI];
        var fonts = [];
        var total = 0;
        for (var i = 0; i < lines.size(); i++) {
            var f = fitFont(dc, lines[i], i == 0 ? labelFont : smaller(labelFont, order), order, w - 6);
            fonts.add(f);
            total += dc.getFontHeight(f);
        }
        var y = top + (h - top - total) / 2;
        for (var i = 0; i < lines.size(); i++) {
            dc.setColor(i == lines.size() - 1 ? COLOR_ACCENT : fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, fonts[i], lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += dc.getFontHeight(fonts[i]);
        }
    }

    // One message, centred in the field below the label, in the label font
    // (smaller only when needed), wrapped over up to 3 lines.
    function drawMessage(dc, fg, top, labelFont, text) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var order = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        var font = Graphics.FONT_XTINY;
        var lines = null;
        var started = false;
        for (var i = 0; i < order.size(); i++) {
            if (order[i] == labelFont) { started = true; }
            if (!started) { continue; }
            var l = wrapText(dc, text, order[i], w - 8);
            if (l.size() <= 3 && l.size() * dc.getFontHeight(order[i]) <= h - top
                    && widest(dc, l, order[i]) <= w - 8) {
                font = order[i];
                lines = l;
                break;
            }
        }
        if (lines == null) {
            lines = wrapText(dc, text, font, w - 8);
        }
        var lineH = dc.getFontHeight(font);
        var y = top + (h - top - lines.size() * lineH) / 2;
        if (y < top) { y = top; }
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(w / 2, y + i * lineH, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function widest(dc, lines, font) {
        var m = 0;
        for (var i = 0; i < lines.size(); i++) {
            var lw = dc.getTextWidthInPixels(lines[i], font);
            if (lw > m) { m = lw; }
        }
        return m;
    }

    // Splits text into lines that fit width. Two lines are balanced
    // ("Shift or press / the Di2 button" rather than a lone last word).
    // Text without spaces (Chinese) is split between characters.
    function wrapText(dc, text, font, width) {
        if (dc.getTextWidthInPixels(text, font) <= width) {
            return [text];
        }
        var words = [];
        var rest = text;
        var sp = rest.find(" ");
        while (sp != null) {
            words.add(rest.substring(0, sp));
            rest = rest.substring(sp + 1, rest.length());
            sp = rest.find(" ");
        }
        words.add(rest);
        var sep = " ";
        if (words.size() == 1) {
            // no spaces: treat every character as a word
            words = [];
            var cs = text.toCharArray();
            for (var i = 0; i < cs.size(); i++) {
                words.add(cs[i].toString());
            }
            sep = "";
        }
        // best split into two lines
        var best = null;
        var bestW = 0;
        for (var k = 1; k < words.size(); k++) {
            var l1 = join(words, 0, k, sep);
            var l2 = join(words, k, words.size(), sep);
            var w1 = dc.getTextWidthInPixels(l1, font);
            var w2 = dc.getTextWidthInPixels(l2, font);
            var mw = w1 > w2 ? w1 : w2;
            if (best == null || mw < bestW) {
                best = [l1, l2];
                bestW = mw;
            }
        }
        if (best != null && bestW <= width) {
            return best;
        }
        // greedy for three or more lines
        var lines = [];
        var cur = "";
        for (var i = 0; i < words.size(); i++) {
            var t = cur.length() == 0 ? words[i] : cur + sep + words[i];
            if (cur.length() == 0 || dc.getTextWidthInPixels(t, font) <= width) {
                cur = t;
            } else {
                lines.add(cur);
                cur = words[i];
            }
        }
        lines.add(cur);
        return lines;
    }

    function join(words, from, to, sep) {
        var s = "";
        for (var i = from; i < to; i++) {
            s += (i > from ? sep : "") + words[i];
        }
        return s;
    }

    function smaller(f, order) {
        for (var i = 0; i < order.size() - 1; i++) {
            if (order[i] == f) { return order[i + 1]; }
        }
        return Graphics.FONT_XTINY;
    }

    // Largest font in order, not bigger than start, that fits width.
    function fitFont(dc, text, start, order, width) {
        var started = false;
        for (var i = 0; i < order.size(); i++) {
            if (order[i] == start) { started = true; }
            if (started && dc.getTextWidthInPixels(text, order[i]) <= width) {
                return order[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    // COG view: front chainring(s) and the active rear cog drawn to scale,
    // connected by the chain. The scale is fixed by the largest chainring and
    // the largest cog so everything always fits and sizes don't jump.
    // Both are drawn hollow so the number on top stays readable.
    function drawDrivetrain(dc, dark, bg, x, y, gw, gh) {
        var idle = dark ? 0x2E2E2E : 0xDCDCDC;
        var active = dark ? 0x5A5A5A : 0xB4B4B4;
        var rings = cfg.rings;
        var cog = cfg.teeth(ble.gear, ble.gearCount);
        var ringT = cfg.ring(ble.front, ble.frontCount);
        if (ringT <= 0) { ringT = rings[0]; }
        var bigRing = rings[0];
        var bigCog = cfg.cogs[0];
        var maxT = bigRing > bigCog ? bigRing : bigCog;

        // pixels per tooth: fit vertically and side by side horizontally
        var margin = 4;
        var k1 = (gh / 2 - 2).toFloat() / maxT;
        var k2 = (gw - 3 * margin).toFloat() / (2 * (bigRing + bigCog));
        var k = k1 < k2 ? k1 : k2;
        if (k * maxT < 6) { return; }
        var cy = y + gh / 2;
        var cx1 = x + margin + (k * bigRing).toNumber();
        var cx2 = x + gw - margin - (k * bigCog).toNumber();
        var r1 = (k * ringT).toNumber();
        var r2 = (k * cog).toNumber();
        if (r2 < 4) { r2 = 4; }

        // chain (upper and lower run)
        dc.setColor(active, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(k * maxT >= 30 ? 3 : 2);
        dc.drawLine(cx1, cy - r1, cx2, cy - r2);
        dc.drawLine(cx1, cy + r1, cx2, cy + r2);
        dc.setPenWidth(1);

        // chainrings, largest first so smaller ones are drawn on top
        for (var i = 0; i < rings.size(); i++) {
            var r = (k * rings[i]).toNumber();
            drawRing(dc, bg, cx1, cy, r, rings[i] == ringT ? active : idle);
        }

        // active cog
        drawRing(dc, bg, cx2, cy, r2, accent());
    }

    function accent() {
        return stale ? COLOR_STALE : COLOR_ACCENT;
    }

    function drawRing(dc, bg, cx, cy, r, color) {
        var thick = (r * 0.22).toNumber();
        if (thick < 2) { thick = 2; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r - thick);
    }
}
