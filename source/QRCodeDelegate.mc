import Toybox.Lang;
import Toybox.WatchUi;

class QRCodeDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        var menu = QRCodeSettings.getIsUsingLargerFont()
            ? new Rez.Menus.MainMenuS()
            : new Rez.Menus.MainMenuL();
        WatchUi.pushView(menu, new QRCodeMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}