import Toybox.Lang;

class Observable {
    //! Keeping WeakReference to an object and a Symbol instead of method to not produce circular refs, thanks to this idea:
    //!
    //! https://forums.garmin.com/developer/connect-iq/f/discussion/3419/should-i-clean-my-circular-reference/23492
    typedef Observer as { :observer as WeakReference, :symbol as Symbol };

    public enum Error {
        //! Can't add an observer twice, because it's already here with the same symbol;
        OBSERVER_EXISTS,
        //! Can't delete an observer, because it's not here;
        OBSERVER_ABSENT,
        //! Observer wrapped with a WeakReference is already deallocated;
        OBSERVER_DEAD,
        //! Observer doesn't support such symbol;
        UNSUPPORTED_SYMBOL
    }

    // Object's HashCode per Observer;
    private var mObservers as Dictionary<Number, Observer>;

    public function initialize() {
        mObservers = {};
    }

    //! Will add new observer if:
    //! - it's not yet deallocated;
    //! - it supports provided symbol;
    //! - it's not already there, or was added previously with a different symbol, then it will overwrite it;
    public function addObserver(observer as WeakReference, symbol as Symbol) as Error? {
        var strongObj = observer.get();
        if (strongObj == null) {
            return OBSERVER_DEAD;
        }
        if(!(strongObj has symbol)) {
            return UNSUPPORTED_SYMBOL;
        }
        var objHash = strongObj.hashCode();
        var existingObserver = mObservers[objHash];
        if (existingObserver != null) {
            if (existingObserver[:symbol].toNumber() == symbol.toNumber()) {
                return OBSERVER_EXISTS;
            }
            mObservers.remove(objHash);
        }
        var observerObj = { :observer => observer, :symbol => symbol };
        mObservers.put(objHash, observerObj);
        return null;
    }

    //! Will remove an observer if:
    //! - it's not yet deallocated;
    //! - it's still there;
    public function removeObserver(observer as WeakReference) as Error? {
        var strongObj = observer.get();
        if (strongObj == null) {
            return OBSERVER_DEAD;
        }
        var objHash = strongObj.hashCode();
        if (mObservers[objHash] == null) {
            return OBSERVER_ABSENT;
        }
        mObservers.remove(objHash);
        return null;
    }

    //! Will notify all observers with given payload;
    //! If any observers are already dead, they'll be immediately removed;
    public function notify(payload as Any?) as Void {
        var keys = mObservers.keys();
        for (var k = 0; k < keys.size(); k += 1) {
            var key = keys[k];
            var observer = mObservers[key];
            var strongObj = observer[:observer].get();
            if (strongObj == null) {
                mObservers.remove(key);
            } else {
                strongObj.method(observer[:symbol]).invoke(payload);
            }
        }
    }
}
