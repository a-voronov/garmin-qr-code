import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;

class QRCodeOptimizer {
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

    typedef Result as Array<String> or Error;
    typedef Callback as Method(status as Status, payload as Float or Result) as Void;

    private var mStatus as Status;
    private var mIteration as Number;
    private var mTimer as Timer?;
    private var mInput as Array?;
    private var mResult as Result?;
    private var mObservable as Observable;

    public function initialize(input as Array) {
        mStatus = IDLE;
        mIteration = 0;
        mInput = input;
        mObservable = new Observable();
    }

    public function getStatus() as Status {
        return mStatus;
    }

    public function getResult() as Float or Result or Null {
        switch (mStatus) {
            case IDLE:
                return null;
            case STARTED:
                return _progress();
            case FINISHED:
                return mResult;
            case STOPPED:
                return null;
        }
    }

    //! Subscribe with a symbol pointing to Method({ :status as Status, :payload as Float or Result }) as Void;
    public function subscribe(observer as WeakReference, symbol as Symbol) as Boolean {
        return mObservable.addObserver(observer, symbol) == null;
    }

    public function unsubscribe(observer as WeakReference) as Boolean {
        return mObservable.removeObserver(observer) == null;
    }

    public function start() as Error? {
        if (mTimer != null or (mStatus != IDLE and mStatus != STOPPED)) {
            return ALREADY_STARTED;
        }
        if (mInput.size() < 1 or !(mInput[0] instanceof Array)) {
            return INVALID_INPUT;
        }
        mStatus = STARTED;
        mResult = [];
        mIteration = 0;
        mTimer = new Timer.Timer();
        mTimer.start(method(:_iterate), QRCodeSettings.getProcessingTimeInterval(), true);

        return null;
    }

    public function stop() as Void {
        if (mTimer == null) {
            return;
        }
        System.println("optimizer stopped");
        mTimer.stop();
        mTimer = null;
        mStatus = STOPPED;
        mIteration = 0;
        mResult = null;
        mObservable.notify({ :status => mStatus, :payload => mResult });
    }

    function _iterate() as Void {
        var string = "";
        var row = mIteration * 4;
        for (var column = 0; column < mInput[row].size(); column += 1) {
            // Creating vertical 4-char column for each item in a row
            var char = [
                _itemOrDefault(mInput, row + 0, column, '0'),
                _itemOrDefault(mInput, row + 1, column, '0'),
                _itemOrDefault(mInput, row + 2, column, '0'),
                _itemOrDefault(mInput, row + 3, column, '0')
            ];
            // Matching vertical 4-char column with corresponding hex-symbol
            if      (_equals(char, ['0', '0', '0', '0'])) { string += "f"; }
            else if (_equals(char, ['0', '0', '0', '1'])) { string += "e"; }
            else if (_equals(char, ['0', '0', '1', '0'])) { string += "d"; }
            else if (_equals(char, ['0', '0', '1', '1'])) { string += "c"; }
            else if (_equals(char, ['0', '1', '0', '0'])) { string += "b"; }
            else if (_equals(char, ['0', '1', '0', '1'])) { string += "a"; }
            else if (_equals(char, ['0', '1', '1', '0'])) { string += "9"; }
            else if (_equals(char, ['0', '1', '1', '1'])) { string += "8"; }
            else if (_equals(char, ['1', '0', '0', '0'])) { string += "7"; }
            else if (_equals(char, ['1', '0', '0', '1'])) { string += "6"; }
            else if (_equals(char, ['1', '0', '1', '0'])) { string += "5"; }
            else if (_equals(char, ['1', '0', '1', '1'])) { string += "4"; }
            else if (_equals(char, ['1', '1', '0', '0'])) { string += "3"; }
            else if (_equals(char, ['1', '1', '0', '1'])) { string += "2"; }
            else if (_equals(char, ['1', '1', '1', '0'])) { string += "1"; }
            else if (_equals(char, ['1', '1', '1', '1'])) { string += "0"; }
            else {
                _finish(INVALID_INPUT);
                return;
            }
        }
        mResult.add(string);
        mObservable.notify({ :status => mStatus, :payload => _progress() });
        mIteration += 1;
        _finishIfNeeded();
    }

    private function _finishIfNeeded() as Void {
        if (mInput.size() <= mIteration * 4) {
            _finish(mResult);
        }
    }

    private function _finish(result as Result) as Void {
        if (mTimer == null) {
            return;
        }
        System.println("optimizer finished");
        mTimer.stop();
        mTimer = null;
        mStatus = FINISHED;
        mResult = result;
        mObservable.notify({ :status => mStatus, :payload => result });
    }

    private function _progress() as Float {
        return (mIteration.toFloat() / Math.ceil(mInput.size() / 4)) * 100;
    }

    private function _itemOrDefault(items as Array, row as Number, column, def as Any) as Any {
        if (row < items.size() and column < items[row].size()) {
            return items[row][column];
        }
        return def;
    }

    private function _equals(lhs as Array, rhs as Array) as Bool {
        if (lhs.size() != rhs.size()) {
            return false;
        }
        for (var i = 0; i < lhs.size(); i += 1) {
            if (lhs[i] != rhs[i]) {
                return false;
            }
        }
        return true;
    }
}
