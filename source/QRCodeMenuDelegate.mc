import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class QRCodeMenuDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        MenuInputDelegate.initialize();
    }

    function onMenuItem(item as Symbol) as Void {
        if (item == :itemClearCache) {
            if (Application has :Storage) {
                Application.Storage.clearValues();
            }
        }
    }
}
