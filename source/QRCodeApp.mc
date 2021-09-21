import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

class QRCodeApp extends Application.AppBase {
    private var mBuilder as QRCodeBuilder;

    function initialize() {
        AppBase.initialize();

        mBuilder = new QRCodeBuilder("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ$%*+-./:", QRCodeBuilder.L);
    }

    function onStart(state as Dictionary?) as Void {

    }

    function onSettingsChanged() as Void {
        // TODO: re-draw screen with new QR
    }

    function onStop(state as Dictionary?) as Void {
        $.log("app.stopped");
        mBuilder.stop();
    }

    function getInitialView() as Array<Views or InputDelegates>? {
        return [ new QRCodeView(mBuilder), new QRCodeDelegate() ] as Array<Views or InputDelegates>;
    }
}

function getApp() as QRCodeApp {
    return Application.getApp() as QRCodeApp;
}

function log(msg as String) as Void {
    // System.println(msg);
}