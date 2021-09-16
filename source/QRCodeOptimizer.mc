import Toybox.Math;
import Toybox.Timer;

typedef QRCodeOptimizable as interface {
    function getStatus() as QRCodeOptimizer.Status;
    function getResult() as QRCodeOptimizer.Result?;
    function start(callback as QRCodeOptimizer.Callback) as QRCodeOptimizer.Error?;
    function stop() as Void;
};

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
    private var mCallback as Callback?;

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

    public function initialize(input as Array) {
        mStatus = IDLE;
        mIteration = 0;
        mInput = input;
    }

    public function start(callback as Callback) as Error? {
        if (mTimer != null or (mStatus != IDLE and mStatus != STOPPED)) {
            return ALREADY_STARTED;
        }
        if (mInput.size() < 1 or !(mInput[0] instanceof Array)) {
            return INVALID_INPUT;
        }
        mStatus = STARTED;
        mResult = [];
        mCallback = callback;
        mIteration = 0;
        mTimer = new Timer.Timer();
        mTimer.start(method(:_iterate), 500, true);

        return null;
    }

    function _iterate() as Void {
        System.println("iteration: " + mIteration);
        var string = "";
        var row = mIteration * 4;
        for (var column = 0; column < mInput[row].size(); column += 1) {
            // Creating vertical 4-char column for each item in a row
            var char = [
                _itemOrDefault(mInput, row + 0, column, true), 
                _itemOrDefault(mInput, row + 1, column, true), 
                _itemOrDefault(mInput, row + 2, column, true), 
                _itemOrDefault(mInput, row + 3, column, true)
            ];
            // Matching vertical 4-char column with corresponding hex-symbol
            if      (_equals(char, [true,  true, true,   true]))  { string += "f"; } 
            else if (_equals(char, [true,  true,  true,  false])) { string += "e"; } 
            else if (_equals(char, [true,  true,  false, true]))  { string += "d"; } 
            else if (_equals(char, [true,  true,  false, false])) { string += "c"; } 
            else if (_equals(char, [true,  false, true,  true]))  { string += "b"; } 
            else if (_equals(char, [true,  false, true,  false])) { string += "a"; } 
            else if (_equals(char, [true,  false, false, true]))  { string += "9"; } 
            else if (_equals(char, [true,  false, false, false])) { string += "8"; } 
            else if (_equals(char, [false, true,  true,  true]))  { string += "7"; } 
            else if (_equals(char, [false, true,  true,  false])) { string += "6"; } 
            else if (_equals(char, [false, true,  false, true]))  { string += "5"; } 
            else if (_equals(char, [false, true,  false, false])) { string += "4"; } 
            else if (_equals(char, [false, false, true,  true]))  { string += "3"; } 
            else if (_equals(char, [false, false, true,  false])) { string += "2"; } 
            else if (_equals(char, [false, false, false, true]))  { string += "1"; } 
            else if (_equals(char, [false, false, false, false])) { string += "0"; }
            else {
                return _finish(INVALID_INPUT);
            }
        }
        mResult.add(string);
        mCallback.invoke(mStatus, _progress());
        mIteration += 1;
        _finishIfNeeded();
    }

    private function _finishIfNeeded() as Void {
        if (mInput.size() <= mIteration * 4) {
            _finish(mResult);
        }
    }

    private function _finish(result as Result) as Void {
        System.println("stop");
        mTimer.stop();
        mStatus = FINISHED;
        mResult = result;
        mCallback.invoke(mStatus, result);
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

    public function stop() as Void {
        if (mTimer == null) {
            return;
        }
        mTimer.stop();
        mTimer = null;
        mStatus = STOPPED;
        mIteration = 0;
        mResult = null;
        mCallback.invoke(mStatus, mResult);
    }
}
