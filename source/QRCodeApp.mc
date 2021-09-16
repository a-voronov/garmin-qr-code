import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class QRCodeApp extends Application.AppBase {
    private var mOptimizer as QRCodeOptimizer;
    private const mCode as Array? = [
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,false,false,false,false,false,false,false,true,true,false,true,false,true,true,false,false,false,false,false,false,false,true,true,true,true,],
        [true,true,true,true,false,true,true,true,true,true,false,true,true,false,false,true,true,true,false,true,true,true,true,true,false,true,true,true,true,],
        [true,true,true,true,false,true,false,false,false,true,false,true,false,false,false,true,true,true,false,true,false,false,false,true,false,true,true,true,true,],
        [true,true,true,true,false,true,false,false,false,true,false,true,false,false,true,false,true,true,false,true,false,false,false,true,false,true,true,true,true,],
        [true,true,true,true,false,true,false,false,false,true,false,true,true,false,false,true,false,true,false,true,false,false,false,true,false,true,true,true,true,],
        [true,true,true,true,false,true,true,true,true,true,false,true,true,false,true,true,false,true,false,true,true,true,true,true,false,true,true,true,true,],
        [true,true,true,true,false,false,false,false,false,false,false,true,false,true,false,true,false,true,false,false,false,false,false,false,false,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,false,true,false,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,false,false,true,false,false,true,true,true,true,true,true,true,true,true,false,false,true,true,true,true,true,true,],
        [true,true,true,true,false,false,true,false,true,false,true,true,false,true,true,true,true,true,false,false,false,true,true,true,true,true,true,true,true,],
        [true,true,true,true,false,false,false,false,false,false,false,true,false,false,true,false,false,false,true,false,true,true,true,true,false,true,true,true,true,],
        [true,true,true,true,true,false,true,true,false,true,true,true,true,false,false,false,false,true,true,false,false,true,false,false,true,true,true,true,true,],
        [true,true,true,true,false,true,true,false,false,true,false,true,true,true,true,false,true,true,false,false,false,false,true,false,false,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,false,false,false,false,true,false,false,true,true,true,false,false,true,true,true,true,true,],
        [true,true,true,true,false,false,false,false,false,false,false,true,false,false,false,true,true,true,false,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,false,true,true,true,true,true,false,true,true,true,false,false,true,false,false,true,true,true,false,false,true,true,true,true,true,],
        [true,true,true,true,false,true,false,false,false,true,false,true,false,true,true,true,false,true,true,true,false,false,false,true,false,true,true,true,true,],
        [true,true,true,true,false,true,false,false,false,true,false,true,false,true,true,true,true,false,false,false,false,true,true,true,true,true,true,true,true,],
        [true,true,true,true,false,true,false,false,false,true,false,true,true,false,true,true,false,false,true,false,false,false,true,false,false,true,true,true,true,],
        [true,true,true,true,false,true,true,true,true,true,false,true,true,false,true,true,true,true,false,false,true,false,true,false,false,true,true,true,true,],
        [true,true,true,true,false,false,false,false,false,false,false,true,true,true,false,true,true,false,true,false,false,true,false,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
        [true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,],
    ] as Array?;

    function initialize() {
        AppBase.initialize();

        mOptimizer = new QRCodeOptimizer(mCode);
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onSettingsChanged() as Void {
        // TODO: re-draw screen with new QR
    }

    function onStop(state as Dictionary?) as Void {
        System.println("app.stopped");
        mOptimizer.stop();
    }

    function getInitialView() as Array<Views or InputDelegates>? {
        return [ new QRCodeView(mOptimizer), new QRCodeDelegate() ] as Array<Views or InputDelegates>;
    }
}

function getApp() as QRCodeApp {
    return Application.getApp() as QRCodeApp;
}
