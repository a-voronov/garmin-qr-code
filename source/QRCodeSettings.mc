import Toybox.Application;
import Toybox.Lang;

module QRCodeSettings {
    private const mCacheKey = "CachedCode";

    private var mIsUsingLargerFont = false;

    function getIsUsingLargerFont() as Boolean {
        return mIsUsingLargerFont;
    }

    function setIsUsingLargerFont(newValue as Boolean) as Void {
        mIsUsingLargerFont = newValue;
    }

    function getCachedCode() as Array<String>? {
        if (Application has :Storage) {
            return Application.Storage.getValue(mCacheKey);
        }
        return null;
    }

    function setCachedCode(newValue as Array<String>?) as Void {
        if (Application has :Storage) {
            Application.Storage.setValue(mCacheKey, newValue);
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
}
