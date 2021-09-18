import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Math;

class QRCodeView extends WatchUi.View {
    private var mErrorMsg as String;
    private var mErrorImg as BitmapResource;
    private var mProcessingMsg as String;
    private var mProcessingImg as BitmapResource;

    private var mFonts = [16];
    private var mOptimizer as QRCodeOptimizable;
    private var mBuilder as QRCodeBuilder;
    private var mProgressBar as WatchUi.ProgressBar?;

    function initialize(builder as QRCodeBuilder, optimizer as QRCodeOptimizable) {
        View.initialize();
        mOptimizer = optimizer;
        mBuilder = builder;

        mErrorMsg = WatchUi.loadResource($.Rez.Strings.ErrorPrompt);
        mErrorImg = WatchUi.loadResource($.Rez.Drawables.ErrorIcon);

        mProcessingMsg = WatchUi.loadResource($.Rez.Strings.ProcessingPrompt);
        mProcessingImg = WatchUi.loadResource($.Rez.Drawables.ProcessingIcon);
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        mFonts = [
            loadResource($.Rez.Fonts.qrcode1),
            loadResource($.Rez.Fonts.qrcode2),
            loadResource($.Rez.Fonts.qrcode3),
            loadResource($.Rez.Fonts.qrcode4),
            loadResource($.Rez.Fonts.qrcode5),
            loadResource($.Rez.Fonts.qrcode6),
            loadResource($.Rez.Fonts.qrcode7),
            loadResource($.Rez.Fonts.qrcode8),
            loadResource($.Rez.Fonts.qrcode9),
            loadResource($.Rez.Fonts.qrcode10),
            loadResource($.Rez.Fonts.qrcode11),
            loadResource($.Rez.Fonts.qrcode12),
            loadResource($.Rez.Fonts.qrcode13),
            loadResource($.Rez.Fonts.qrcode14),
            loadResource($.Rez.Fonts.qrcode15),
            loadResource($.Rez.Fonts.qrcode16)
		];
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);

        // Clears the screen of device with background color (Graphics.COLOR_WHITE)
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        // var cachedCode = QRCodeSettings.getCachedCode();
        // if (cachedCode != null) {
        //     _drawQRText(cachedCode, dc);
        //     return;
        // }

        if (mBuilder.getStatus() == QRCodeBuilder.IDLE and mBuilder.start() == null) {
            mBuilder.subscribe(weak(), :_handleBuilderStatus);
            mProgressBar = new WatchUi.ProgressBar(mProcessingMsg, 0);
            // TODO: handle back button in delegate
            WatchUi.pushView(mProgressBar, new $.ProgressDelegate(method(:_stopBuilder)), WatchUi.SLIDE_BLINK);
        }

        if (mBuilder.getStatus() == QRCodeBuilder.FINISHED) {
            // _drawQRText(mBuilder.getResult(), dc);
            System.println("builder result: " + mBuilder.getResult());
        }

        // if (mOptimizer.getStatus() == QRCodeOptimizer.IDLE and mOptimizer.start() == null) {
        //     mOptimizer.subscribe(weak(), :_handleOptimizerStatus);
        //     mProgressBar = new WatchUi.ProgressBar(mProcessingMsg, 0);
        //     // TODO: handle back button in delegate
        //     WatchUi.pushView(mProgressBar, new $.ProgressDelegate(method(:_stopOptimizer)), WatchUi.SLIDE_BLINK);
        // }

        // if (mOptimizer.getStatus() == QRCodeOptimizer.FINISHED) {
        //     _drawQRText(mOptimizer.getResult(), dc);
        // }
    }

    private function _drawQRText(result as QRCodeOptimizer.Result or Float or Null, dc as DC) as Void {
        if ((result instanceof Array) and result.size() > 0) {
            var params = _getDrawingParams(dc, result[0].length());
            var font = mFonts[params[:charSize] - 1];
            var centerX = params[:x] + params[:size] / 2;

            for (var line = 0; line < result.size(); line += 1) {
                var string = result[line];
                if (!(string instanceof String)) {
                    continue;
                }
                dc.drawText(centerX, params[:y] + (line * 4 * params[:charSize]), font, string, Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else if (result instanceof Float) {
            _drawTextWithImage(Math.ceil(result).toNumber() + "%", mProcessingImg, dc);
        } else {
            _drawTextWithImage(mErrorMsg, mErrorImg, dc);
        }
    }

    private function _drawTextWithImage(text as String, image as BitmapResource, dc as DC) as Void {
        var centerX = dc.getWidth() / 2;
        var centerY = dc.getHeight() / 2;
        var font = Graphics.FONT_LARGE;
        dc.drawText(centerX, centerY - dc.getTextDimensions(text, font)[1] - 5, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawBitmap(centerX - image.getWidth() / 2, centerY + 5, image);
    }

    function _handleOptimizerStatus(args as { :status as QRCodeOptimizer.Status, :payload as Float or QRCodeOptimizer.Result}) as Void {
        var status = args[:status];
        var payload = args[:payload];
        if (status == QRCodeOptimizer.STARTED and payload instanceof Float) {
            mProgressBar.setProgress(payload);
        } else if (status == QRCodeOptimizer.FINISHED) {
            WatchUi.popView(WatchUi.SLIDE_BLINK);
            QRCodeSettings.setCachedCode(payload);
        } else if (status == QRCodeOptimizer.STOPPED) {
            WatchUi.popView(WatchUi.SLIDE_BLINK);
        }
    }

    function _handleBuilderStatus(args as { :status as QRCodeBuilder.Status, :payload as Float or QRCodeBuilder.Result}) as Void {
        var status = args[:status];
        var payload = args[:payload];
        if (status == QRCodeBuilder.STARTED and payload instanceof Float) {
            System.println("view.builder started: " + payload);
            mProgressBar.setProgress(payload);
        } else if (status == QRCodeBuilder.FINISHED) {
            System.println("view.builder finished");
            WatchUi.popView(WatchUi.SLIDE_BLINK);
        } else if (status == QRCodeBuilder.STOPPED) {
            System.println("view.builder stopped");
            WatchUi.popView(WatchUi.SLIDE_BLINK);
        }
    }

    function _stopOptimizer() {
        mOptimizer.stop();
    }

    function _stopBuilder() {
        mBuilder.stop();
    }

    // TODO: simplify _getDrawingParams to return center x, y instead of origin

    (:regular)
    private function _getDrawingParams(dc as Dc, codeSize as Number) as { :x as Number, :y as Number, :size as Number, :charSize as Number } {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var centerX = screenWidth / 2;
        var centerY = screenHeight / 2;
        var areaSize = screenWidth < screenHeight ? screenWidth : screenHeight;
        var charSize = QRCodeSettings.getIsUsingLargerFont()
            ? Math.ceil(areaSize / codeSize)
            : Math.floor(areaSize / codeSize);
        charSize = charSize < 1 ? 1 : charSize;
        charSize = charSize > 16 ? 16 : charSize;
        areaSize = charSize * codeSize;
        var halfAreaSize = areaSize / 2;
        var x = centerX - halfAreaSize;
        var y = centerY - halfAreaSize;

        return { :x => x, :y => y, :size => areaSize, :charSize => charSize.toNumber() };
    }

    (:round)
    private function _getDrawingParams(dc as Dc, codeSize as Number) as { :x as Number, :y as Number, :size as Number, :charSize as Number } {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var screenCenterX = screenWidth / 2;
        var screenCenterY = screenHeight / 2;
        var screenSize = screenWidth < screenHeight ? screenWidth : screenHeight;
        var screenRadius = screenSize / 2;
        var areaSize = screenRadius * Math.sqrt(2);
        var charSize = QRCodeSettings.getIsUsingLargerFont()
            ? Math.ceil(areaSize / codeSize)
            : Math.floor(areaSize / codeSize);
        charSize = charSize < 1 ? 1 : charSize;
        charSize = charSize > 16 ? 16 : charSize;
        areaSize = charSize * codeSize;
        var areaRadius = areaSize / 2;
        var x = screenCenterX - areaRadius;
        var y = screenCenterY - areaRadius;

        return { :x => x, :y => y, :size => areaSize, :charSize => charSize.toNumber() };
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {

    }
}

//! Input handler for the progress bar
class ProgressDelegate extends WatchUi.BehaviorDelegate {
    private var _callback as Method() as Void;

    //! Constructor
    //! @param callback Callback function
    public function initialize(callback as Method() as Void) {
        BehaviorDelegate.initialize();
        _callback = callback;
    }

    //! Handle back behavior
    //! @return true if handled, false otherwise
    public function onBack() as Boolean {
        _callback.invoke();
        return true;
    }
}
