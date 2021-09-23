import Toybox.Lang;

class QRCodeController {
    enum Status {
        // Associates with null payload
        IDLE, STOPPED,
        // Associates with Float (0-100) payload
        STARTED,
        // Associates with Result payload
        FINISHED
    }

    enum Error {
        INVALID_INPUT,
        ALREADY_STARTED,
        UNKNOWN
    }

    typedef CodeData as QRCodeBuilder.CodeData;
    typedef Result as QRCodeFormatter.Result;

    private var mUsingCache = false;
    private var mBuilder as QRCodeBuilder?;
    private var mFormatter as QRCodeFormatter?;
    private const mObservable = new Observable();

    public function getStatus() as Status {
        if (mUsingCache) {
            return FINISHED;
        }
        if (mBuilder == null) {
            return IDLE;
        }
        // If builder has finished, then we clarify status from formatter as a following item in the pipeline
        var builderStatus = mBuilder.getStatus();
        if (builderStatus != FINISHED) {
            switch (builderStatus) {
                case IDLE: return IDLE;
                case STARTED: return STARTED;
                case STOPPED: return STOPPED;
                case FINISHED: return STARTED;
            }
        }
        // If builder is finished with error without having initialized formatter, then whole pipeline is finished
        // otherwise, it can be some intermediate state, so treating as still ongoing
        if (mFormatter == null) {
            if (mBuilder.getResult() instanceof Number) {
                return FINISHED;
            }
            return STARTED;
        }
        // Any non-ended formatter state is treated as started, because we're in the middle of pipeline
        switch (mFormatter.getStatus()) {
            case IDLE: return STARTED;
            case STARTED: return STARTED;
            case STOPPED: return STOPPED;
            case FINISHED: return FINISHED;
        }
    }

    public function getResult() as Float or Result or Null {
        if (mUsingCache) {
            return QRCodeSettings.getCachedCode();
        }
        if (mBuilder == null) {
            return null;
        }
        if (mBuilder.getStatus() != FINISHED) {
            var result = mBuilder.getResult();
            if (result instanceof Float) {
                return result * 0.75;
            }
            return result;
        }
        if (mFormatter == null) {
            var result = mBuilder.getResult();
            if (result instanceof Number) {
                return result;
            }
            return 75.0;
        }
        var result = mFormatter.getResult();
        if (result == null or (result instanceof Float)) {
            return 75.0 + (result * 0.25);
        }
        return result;
    }

    public function start() as Error? {
        if (mBuilder != null) {
            return ALREADY_STARTED;
        }

        var cachedCode = QRCodeSettings.getCachedCode();
        if (cachedCode != null and (cachedCode instanceof Array)) {
            mUsingCache = true;
            _notifyObservers();
            return null;
        } else {
            mUsingCache = false;
        }

        mFormatter = null;
        mBuilder = new QRCodeBuilder(QRCodeSettings.getInputCode(), QRCodeBuilder.L);
        mBuilder.subscribe(weak(), :_handleBuilderStatus);
        return mBuilder.start();
    }

    function _handleBuilderStatus(args as { :status as QRCodeBuilder.Status, :payload as Float or QRCodeBuilder.Result}) as Void {
        var status = args[:status];
        var payload = args[:payload];

        _notifyObservers();

        if (status == FINISHED and (payload instanceof Array) and mFormatter == null) {
            mFormatter = new QRCodeFormatter(payload);
            mFormatter.subscribe(weak(), :_handleFormatterStatus);
            mFormatter.start();
        }
    }

    function _handleFormatterStatus(args as { :status as QRCodeFormatter.Status, :payload as Float or QRCodeFormatter.Result}) as Void {
        var status = args[:status];
        var payload = args[:payload];

        _notifyObservers();

        if (status == FINISHED and (payload instanceof Array)) {
            QRCodeSettings.setCachedCode(payload);
        }
    }

    private function _notifyObservers() as Void {
        mObservable.notify({ :status => getStatus(), :payload => getResult() });
    }

    public function restart() as Void {
        if (getStatus() == IDLE) {
            start();
        } else {
            stop();
            mBuilder = null;
            mFormatter = null;
            start();
        }
    }

    public function stop() as Void {
        if (mBuilder != null) {
            mBuilder.stop();
        }
        if (mFormatter != null) {
            mFormatter.stop();
        }
    }

    public function subscribe(observer as WeakReference, symbol as Symbol) as Boolean {
        return mObservable.addObserver(observer, symbol) == null;
    }

    public function unsubscribe(observer as WeakReference) as Boolean {
        return mObservable.removeObserver(observer) == null;
    }
}