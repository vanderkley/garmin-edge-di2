import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

// BLE link to a Shimano 12-speed wireless rear derailleur (tested: RD-M8250).
//
// Protocol (verified on Edge Explore 2 fw 30.22, see logs/):
//  - Battery: standard 0x180F / 0x2A19, 1 byte percent.
//  - Gear:    service 000018EF-5348-494D-414E-4F5F424C4500, char 2AC1 notify.
//             17-byte packet: byte5 = rear gear (1 = largest cog), byte6 = gear count.
//  - D-FLY:   same service, char 2AC2 indicate (works WITHOUT bond).
//             [counter, ch1, ch2, ch3, ch4]; 0xF0 = unassigned; per channel
//             high nibble = event (1 short, 2 long start, 3 long repeat,
//             4 double, 0 released), low nibble = per-channel counter.
//
// Firmware notes:
//  - fw 31.33: registerProfile with a custom 128-bit UUID returns status 2 and
//    any registerProfile after that crashes the app. So the Shimano service is
//    registered FIRST and nothing is registered after a failure.
//  - Bonding (CONNECTION_STRATEGY_SECURE_PAIR_BOND) froze the Edge on 30.22:
//    never bond.
class Di2Ble extends BluetoothLowEnergy.BleDelegate {
    enum {
        ST_REGISTER, ST_FW_UNSUPPORTED, ST_SCAN, ST_CONNECTING, ST_SETUP, ST_READY
    }

    const CONNECT_TIMEOUT_MS = 20000;
    const BATTERY_POLL_MS = 300000;
    const STALE_MS = 30000;       // keep showing the last gear (grey) this long

    var state = ST_REGISTER;

    // public data
    var gear = 0;            // 0 = unknown
    var gearCount = 12;
    var front = 0;           // 0 = no front derailleur / unknown
    var frontCount = 0;
    var battery = -1;        // -1 = unknown
    var dflyEvents = [];
    var lostAt = 0;
    var lastGearHex = "";    // raw 2AC1 packet, logged on change (helps verify 2x systems)          // System.getTimer() when the link dropped, 0 = not lost     // queue of :short / :long / :double, consumed by the view

    // UUIDs
    var svcShimano;
    var chrGear;
    var chrDfly;
    var svcBatt;
    var chrBatt;
    var svcShimanoCfg;

    var regQueue = [];
    var device = null;
    var target = null;
    var connectStartedAt = 0;
    var lastBatteryRead = 0;
    var ops = [];
    var opBusy = false;
    var chCounter = [-1, -1, -1, -1, -1];
    var chLongActive = [false, false, false, false, false];

    function initialize() {
        BleDelegate.initialize();
        svcShimano = BluetoothLowEnergy.stringToUuid("000018ef-5348-494d-414e-4f5f424c4500");
        svcShimanoCfg = BluetoothLowEnergy.stringToUuid("000018ff-5348-494d-414e-4f5f424c4500");
        chrGear = BluetoothLowEnergy.stringToUuid("00002ac1-5348-494d-414e-4f5f424c4500");
        chrDfly = BluetoothLowEnergy.stringToUuid("00002ac2-5348-494d-414e-4f5f424c4500");
        svcBatt = BluetoothLowEnergy.stringToUuid("0000180f-0000-1000-8000-00805f9b34fb");
        chrBatt = BluetoothLowEnergy.stringToUuid("00002a19-0000-1000-8000-00805f9b34fb");
    }

    function log(msg) {
        System.println(System.getTimer() + " " + msg);
    }

    function isConnected() {
        return state == ST_SETUP || state == ST_READY;
    }

    // Link lost recently: the last known values are still shown, in grey.
    function isStale() {
        if (isConnected() || lostAt == 0 || gear <= 0) {
            return false;
        }
        if (System.getTimer() - lostAt > STALE_MS) {
            gear = 0;
            lostAt = 0;
            return false;
        }
        return true;
    }

    // ---------- lifecycle ----------
    function start() {
        var cccd = BluetoothLowEnergy.cccdUuid();
        regQueue = [
            { :uuid => svcShimano, :characteristics => [
                { :uuid => chrGear, :descriptors => [cccd] },
                { :uuid => chrDfly, :descriptors => [cccd] } ] },
            { :uuid => svcBatt, :characteristics => [
                { :uuid => chrBatt, :descriptors => [cccd] } ] }
        ];
        registerNext();
    }

    function stop() {
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            if (device != null) {
                BluetoothLowEnergy.unpairDevice(device);
            }
        } catch (e) {
        }
    }

    // Called once per second by the view.
    function tick() {
        var now = System.getTimer();
        if (state == ST_CONNECTING && now - connectStartedAt > CONNECT_TIMEOUT_MS) {
            log("connect timeout, rescanning");
            dropDevice();
            startScan();
        } else if (state == ST_READY && now - lastBatteryRead > BATTERY_POLL_MS && !opBusy) {
            lastBatteryRead = now;
            ops.add([:read, svcBatt, chrBatt, 0]);
            nextOp();
        }
    }

    // ---------- registration ----------
    function registerNext() {
        if (regQueue.size() == 0) {
            startScan();
            return;
        }
        var p = regQueue[0];
        regQueue = regQueue.slice(1, null);
        try {
            BluetoothLowEnergy.registerProfile(p);
        } catch (e) {
            log("registerProfile exception " + e.getErrorMessage());
            failRegistration();
        }
    }

    function onProfileRegister(uuid, status) {
        log("profile " + uuid + " status " + status);
        if (status != 0) {
            failRegistration();
            return;
        }
        registerNext();
    }

    function failRegistration() {
        // Never call registerProfile again (crashes on fw 31.33).
        regQueue = [];
        state = ST_FW_UNSUPPORTED;
    }

    // ---------- scanning / connecting ----------
    function startScan() {
        state = ST_SCAN;
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function onScanResults(scanResults) {
        if (state != ST_SCAN) {
            return;
        }
        for (var r = scanResults.next(); r != null; r = scanResults.next()) {
            if (isShimano(r)) {
                connect(r);
                return;
            }
        }
    }

    function isShimano(r) {
        var it = r.getServiceUuids();
        for (var u = it.next(); u != null; u = it.next()) {
            if (u.equals(svcShimano) || u.equals(svcShimanoCfg)) {
                return true;
            }
        }
        // manufacturer data with company id 0x044A (Shimano)
        var raw = r.getRawData();
        if (raw == null) {
            return false;
        }
        var i = 0;
        while (i + 3 < raw.size()) {
            var len = raw[i];
            if (len == 0) {
                break;
            }
            if (raw[i + 1] == 0xFF && raw[i + 2] == 0x4A && raw[i + 3] == 0x04) {
                return true;
            }
            i += len + 1;
        }
        return false;
    }

    function connect(r) {
        try {
            target = r;
            state = ST_CONNECTING;
            connectStartedAt = System.getTimer();
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            device = BluetoothLowEnergy.pairDevice(r);
            log("pairing");
        } catch (e) {
            log("pairDevice exception " + e.getErrorMessage());
            dropDevice();
            startScan();
        }
    }

    function dropDevice() {
        try {
            if (device != null) {
                BluetoothLowEnergy.unpairDevice(device);
            }
        } catch (e) {
        }
        device = null;
        ops = [];
        opBusy = false;
    }

    function onConnectedStateChanged(dev, cstate) {
        if (cstate == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            log("connected");
            device = dev;
            lostAt = 0;
            state = ST_SETUP;
            chCounter = [-1, -1, -1, -1, -1];
            ops = [
                [:read, svcBatt, chrBatt, 0],
                [:cccd, svcShimano, chrGear, 0x01],   // notifications
                [:cccd, svcShimano, chrDfly, 0x02],   // indications
                [:cccd, svcBatt, chrBatt, 0x01]
            ];
            opBusy = false;
            lastBatteryRead = System.getTimer();
            nextOp();
        } else {
            log("disconnected");
            dropDevice();
            if (gear > 0) {
                lostAt = System.getTimer();   // keep last gear, shown grey for a while
            }
            startScan();
        }
    }

    // ---------- GATT operations (one at a time) ----------
    function nextOp() {
        if (opBusy || device == null) {
            return;
        }
        while (ops.size() > 0) {
            var op = ops[0];
            ops = ops.slice(1, null);
            var svc = device.getService(op[1]);
            var chr = (svc == null) ? null : svc.getCharacteristic(op[2]);
            if (chr == null) {
                continue;
            }
            try {
                if (op[0] == :read) {
                    chr.requestRead();
                } else {
                    var d = chr.getDescriptor(BluetoothLowEnergy.cccdUuid());
                    if (d == null) {
                        continue;
                    }
                    d.requestWrite([op[3], 0x00]b);
                }
                opBusy = true;
                return;
            } catch (e) {
                log("op exception " + e.getErrorMessage());
            }
        }
        if (state == ST_SETUP) {
            state = ST_READY;
        }
    }

    function onCharacteristicRead(chr, status, value) {
        if (chr.getUuid().equals(chrBatt) && status == BluetoothLowEnergy.STATUS_SUCCESS) {
            setBattery(value);
        }
        opBusy = false;
        nextOp();
    }

    function onDescriptorWrite(desc, status) {
        opBusy = false;
        nextOp();
    }

    function onCharacteristicChanged(chr, value) {
        if (value == null) {
            return;
        }
        var u = chr.getUuid();
        if (u.equals(chrGear)) {
            if (value.size() == 17) {
                var hex = toHex(value);
                if (!hex.equals(lastGearHex)) {
                    lastGearHex = hex;
                    log("gear raw " + hex);
                }
                var g = value[5];
                var m = value[6];
                if (m >= 1 && m <= 13 && g >= 1 && g <= m) {
                    gear = g;
                    gearCount = m;
                }
                // Front derailleur: bytes 3/4 are FF FF on a 1x system (RD-M8250).
                // Assumed: byte3 = front position, byte4 = number of rings (unverified on 2x).
                var f = value[3];
                var fm = value[4];
                if (fm >= 2 && fm <= 3 && f >= 1 && f <= fm) {
                    front = f;
                    frontCount = fm;
                } else {
                    front = 0;
                    frontCount = 0;
                }
            }
        } else if (u.equals(chrDfly)) {
            parseDfly(value);
        } else if (u.equals(chrBatt)) {
            setBattery(value);
        }
    }

    function setBattery(value) {
        if (value != null && value.size() > 0 && value[0] <= 100) {
            battery = value[0];
        }
    }

    function parseDfly(v) {
        if (v.size() < 5) {
            return;
        }
        for (var ch = 1; ch <= 4; ch++) {
            var b = v[ch];
            if (b == 0xF0) {
                continue;
            }
            var counter = b & 0x0F;
            if (counter == chCounter[ch]) {
                continue; // repeated indication
            }
            chCounter[ch] = counter;
            var type = (b >> 4) & 0x0F;
            if (type == 1) {
                dflyEvents.add(:short);
            } else if (type == 2) {
                chLongActive[ch] = true;
                dflyEvents.add(:long);
            } else if (type == 4) {
                dflyEvents.add(:double);
            } else if (type == 0) {
                chLongActive[ch] = false;
            }
            // type 3 (long repeat) intentionally ignored
        }
    }

    function toHex(b) {
        var s = "";
        for (var i = 0; i < b.size(); i++) {
            s += b[i].format("%02X");
        }
        return s;
    }

    // Returns and clears pending D-FLY events.
    function takeEvents() {
        var e = dflyEvents;
        dflyEvents = [];
        return e;
    }
}
