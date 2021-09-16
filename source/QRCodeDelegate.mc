import Toybox.Lang;
import Toybox.WatchUi;

class QRCodeDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new QRCodeMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}