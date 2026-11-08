import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.WatchUi;

// Di2 Gear & Battery: Connect IQ data field for Shimano 12-speed wireless Di2
// (and Di2 systems exposing the same BLE service) on Edge devices.
// Shows gear, cog, ratio, battery and learned battery range; the D-FLY
// button switches what is shown (short = next, long = previous, double = gear).
class Di2App extends Application.AppBase {
    var ble as Di2Ble?;
    var cfg as Di2Config?;
    var view = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        cfg = new Di2Config();
        ble = new Di2Ble();
        BluetoothLowEnergy.setDelegate(ble);
        Di2Demo.start(ble);
    }

    function onStop(state as Dictionary?) as Void {
        if (view != null) {
            view.onStop();
        }
        if (ble != null) {
            ble.stop();
        }
    }

    function onSettingsChanged() as Void {
        if (cfg != null) {
            cfg.load();
        }
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        view = new Di2View(ble, cfg);
        return [view];
    }
}
