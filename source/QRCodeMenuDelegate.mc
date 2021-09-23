import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class QRCodeMenuDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        MenuInputDelegate.initialize();
    }

    function onMenuItem(item as Symbol) as Void {
        if (item == :itemClearCache) {
            QRCodeSettings.clearCache();
            $.getApp().getQRCodeController().restart();
        } else if (item == :itemTryLargerFont) {
            QRCodeSettings.setIsUsingLargerFont(true);
        } else if (item == :itemTrySmallerFont) {
            QRCodeSettings.setIsUsingLargerFont(false);
        }
    }
}
