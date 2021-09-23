import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

class QRCodeApp extends Application.AppBase {
    private var mController as QRCodeController;

    function getQRCodeController() as QRCodeController {
        return mController;
    }

    function initialize() {
        AppBase.initialize();

        mController = new QRCodeController();
    }

    function onStart(state as Dictionary?) as Void {
        // TODO: comment these lines if you want to get code entirely from the properties, without demo code.
        var code = QRCodeSettings.getInputCode();
        if (code == null or code.length() == 0) {
            QRCodeSettings.setInputCode(QRCodeSettings.demoCode());
        }
    }

    function onSettingsChanged() as Void {
        QRCodeSettings.clearCache();
        mController.restart();
    }

    function onStop(state as Dictionary?) as Void {
        $.log("app.stopped");
        mController.stop();
    }

    function getInitialView() as Array<Views or InputDelegates>? {
        return [ new QRCodeView(mController), new QRCodeDelegate() ] as Array<Views or InputDelegates>;
    }
}

function getApp() as QRCodeApp {
    return Application.getApp() as QRCodeApp;
}

function log(msg as String) as Void {
    System.println(msg);
}