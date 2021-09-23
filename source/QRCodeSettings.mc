import Toybox.Application;
import Toybox.Lang;

module QRCodeSettings {
    private const mCodeKey = "Code";
    private const mCacheKey = "CachedCode";

    private var mIsUsingLargerFont = false;

    function getIsUsingLargerFont() as Boolean {
        return mIsUsingLargerFont;
    }

    function setIsUsingLargerFont(newValue as Boolean) as Void {
        mIsUsingLargerFont = newValue;
    }

    function getInputCode() as String? {
        if (Application has :Properties) {
            return Application.Properties.getValue(mCodeKey);
        }
        return null;
    }

    function setInputCode(newValue as String?) as Void {
        if (Application has :Properties) {
            Application.Properties.setValue(mCodeKey, newValue);
        }
    }

    function getCachedCode() as Array<String>? {
        if (Application has :Storage) {
            return Application.Storage.getValue(mCacheKey);
        } else if (Application.AppBase has :Properties) {
            return Application.AppBase.Properties.getValue(mCacheKey);
        }
        return null;
    }

    function setCachedCode(newValue as Array<String>?) as Void {
        if (Application has :Storage) {
            Application.Storage.setValue(mCacheKey, newValue);
        } else if (Application.AppBase has :Properties) {
            Application.AppBase.Properties.setValue(mCacheKey, newValue);
        }
    }

    function clearCache() as Void {
        if (Application has :Storage) {
            Application.Storage.clearValues();
        }
    }

    function getProcessingTimeInterval() as Number {
        return 50;
    }

    function getBuildingTimeInterval() as Number {
        return 50;
    }

    function criticalInputSize() as Number {
        return 250;
    }

    function demoCode() as String {
        return "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
    }
}
