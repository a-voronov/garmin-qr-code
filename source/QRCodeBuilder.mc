import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;

class QRCodeBuilder {
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

    enum Mode {
        NUMERIC = 1,
        ALPHANUMERIC = 2,
        BINARY = 4,
        KANJI = 8
    }

    enum QRError {
        L = 7,
        M = 15,
        Q = 25,
        H = 30
    }

    enum Progress {
        ADD_DATA_PREPARE,
        ADD_DATA_ENCODE,
        ADD_DATA_TERMINATE_BITS_AND_PROCESS_WORDS,
        ADD_DATA_NUMERIC_REPRESENTATION,
        ADD_DATA_DATA_BLOCKS,
        ADD_DATA_DATA_BLOCKS_INTO_BUFFER,

        MAKE_CODE_ADD_PATTERNS,
        MAKE_CODE_MAKE_MASKS,
        MAKE_CODE_CHOOSE_BEST_MASK
    }

    typedef Numbers as Array<Number>;
    typedef NumbersOrNulls as Array<Number?>;

    typedef CodeBlock as Array<Char>;
    typedef CodeData as Array<CodeBlock>;
    typedef CodeMasks as Array<CodeData>;
    typedef Result as CodeData or Error;

    private const mMode as Mode = ALPHANUMERIC;
    private const mStepsToFinish = 9;

    private var mInput as String;
    private var mError as QRError;
    private var mVersion as Number;

    private var mObservable as Observable;
    private var mTimer as Timer?;
    private var mProgress as Progress?;
    private var mProgressPayload as Dictionary;

    private var mStatus as Status;
    private var mData as String?;
    private var mMasks as CodeMasks?;
    private var mMaskIdx as Number?;
    private var mStatusError as Error?;

    function initialize(code as String, error as QRError) {
        mInput = code.toUpper();
        mError = error;
        mVersion = _bestVersion();
        mObservable = new Observable();
        mStatus = IDLE;

        $.log("mVersion: " + mVersion);
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
                if (mStatusError != null) {
                    return mStatusError;
                }
                if (mMasks == null or mMaskIdx == null) {
                    return UNKNOWN;
                }
                return mMasks[mMaskIdx];
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
        if (mTimer != null) {
            return ALREADY_STARTED;
        }
        // Create the binary data block.
        // And with this, create the actual QR code.
        mData = "";
        mProgress = 0;
        mStatus = STARTED;
        mTimer = new Timer.Timer();
        mTimer.start(method(:_iterate), QRCodeSettings.getBuildingTimeInterval(), true);
        return null;
    }

    public function stop() as Void {
        if (mTimer == null) {
            return;
        }
        $.log("builder stopped");
        mTimer.stop();
        mTimer = null;
        mProgress = null;
        mProgressPayload = {};
        mStatus = STOPPED;

        mData = null;
        mMasks = null;
        mMaskIdx = null;
        mStatusError = null;

        mObservable.notify({ :status => getStatus(), :payload => getResult() });
    }

    private function _finish(error as Error?) as Void {
        if (mTimer == null) {
            return;
        }
        $.log("builder finished: " + error);
        mTimer.stop();
        mTimer = null;
        mProgress = null;
        mProgressPayload = {};
        mStatus = FINISHED;
        mStatusError = error;

        mObservable.notify({ :status => getStatus(), :payload => getResult() });
    }

    private function _progress() as Float {
        var subCurrent = mProgressPayload[:current];
        var subTotal = mProgressPayload[:total];
        var subProgress = 0;
        if (subTotal != null and subCurrent != null) {
            subProgress = ((subCurrent.toFloat() / subTotal) * 100) / mStepsToFinish;
        }
        return ((mProgress.toFloat() / mStepsToFinish) * 100) + subProgress;
    }

    // ***************************************************************
    // *                          ADD DATA                           *
    // ***************************************************************

    function _iterate() as Void {
        switch (mProgress) {
            case ADD_DATA_PREPARE:
            case ADD_DATA_ENCODE:
            case ADD_DATA_TERMINATE_BITS_AND_PROCESS_WORDS:
            case ADD_DATA_NUMERIC_REPRESENTATION:
            case ADD_DATA_DATA_BLOCKS:
            case ADD_DATA_DATA_BLOCKS_INTO_BUFFER:
                try {
                    _iterateAddData();
                } catch (e instanceof Lang.SerializationException) {
                    _finish(INVALID_INPUT);
                    return;
                } catch (e) {
                    if (e instanceof Lang.Exception) {
                        $.log("Error: " + e.getErrorMessage());
                        e.printStackTrace();
                    }
                    _finish(UNKNOWN);
                    return;
                }
                break;

            case MAKE_CODE_ADD_PATTERNS:
            case MAKE_CODE_MAKE_MASKS:
            case MAKE_CODE_CHOOSE_BEST_MASK:
                _iterateMakeCode();
                break;
        }
        mObservable.notify({ :status => mStatus, :payload => _progress() });

        var subCurrent = mProgressPayload[:current];
        var subTotal = mProgressPayload[:total];
        if ((subTotal != null and subCurrent != null) and subCurrent < subTotal) {
            return;
        }
        mProgressPayload.remove(:current);
        mProgressPayload.remove(:total);
        mProgress += 1;
        _finishIfNeeded();
    }

    private function _finishIfNeeded() as Void {
        if (mProgress >= mStepsToFinish) {
            _finish(null);
        }
    }

    //! This function properly constructs a QR code's data string.
    //! It takes into account the interleaving pattern required by the standard.
    private function _iterateAddData() as Void {
        switch (mProgress) {
            case ADD_DATA_PREPARE: {
                $.log("ADD_DATA_PREPARE");
                // Encode the data into a QR code
                mData += _binaryString(mMode, 4);
                mData += _dataLength();
                $.log("mData: " + mData);
                mProgressPayload = {};
                break;
            }

            case ADD_DATA_ENCODE: {
                $.log("ADD_DATA_ENCODE");
                _encodeAlphaNumeric();
                break;
            }

            case ADD_DATA_TERMINATE_BITS_AND_PROCESS_WORDS: {
                $.log("ADD_DATA_TERMINATE_BITS_AND_PROCESS_WORDS");
                // As per the standard, terminating bits are only supposed to be added after the bit stream is complete
                var bits = _terminateBits(mData);
                if (bits != null) {
                    mData += bits;
                }
                // _delimitWords and _addWords can return Null
                var addBits = _delimitWords();
                if (addBits != null) {
                    mData += addBits;
                }
                var fillBytes = _addWords();
                if (fillBytes != null) {
                    mData += fillBytes;
                }
                mProgressPayload = {};
                break;
            }

            case ADD_DATA_NUMERIC_REPRESENTATION: {
                $.log("ADD_DATA_NUMERIC_REPRESENTATION");
                // Get a numeric representation of the data
                if (!mProgressPayload.hasKey(:current)) {
                    var data as Numbers = [];
                    var chunks as Array<CodeBlock> = _grouped(8, mData.toCharArray(), null);
                    mProgressPayload = { :current => 0, :total => chunks.size(), :chunks => chunks, :data => data };
                } else {
                    var chunks = mProgressPayload[:chunks];
                    var i = mProgressPayload[:current];
                    var chunk = chunks[i];
                    var string = "";
                    for (var c = 0; c < chunk.size(); c += 1) {
                        string += chunk[c].toString();
                    }
                    mProgressPayload[:data].add(string.toNumberWithBase(2));
                    mProgressPayload[:current] += 1;
                    if (mProgressPayload[:current] < mProgressPayload[:total]) {
                        return;
                    }
                }
                break;
            }

            case ADD_DATA_DATA_BLOCKS: {
                $.log("ADD_DATA_DATA_BLOCKS");

                if (!mProgressPayload.hasKey(:current)) {
                    var data = mProgressPayload[:data];
                    // This is the error information for the code
                    var errorInfo as Numbers = QRCodeTables.eccwbi[mVersion][QRCodeTables.error[mError]];
                    // This will hold our data blocks
                    var dataBlocks as Array<NumbersOrNulls> = [];
                    // This will hold our error blocks
                    var errorBlocks as Array<Numbers> = [];
                    // Some codes have the data sliced into two different sized blocks
                    // for example, first two 14 word sized blocks, then four 15 word sized blocks.
                    // This means that slicing size can change over time.
                    var dataBlockSizes = _mult([errorInfo[2]], errorInfo[1]);
                    if (errorInfo[3] != 0) {
                        dataBlockSizes.addAll(_mult([errorInfo[4]], errorInfo[3]));
                    }
                    $.log("data: " + data);
                    // For every block of data, slice the data into the appropriate sized block
                    var currentByte = 0;
                    for (var i = 0; i < dataBlockSizes.size(); i += 1) {
                        var nDataBlocks = dataBlockSizes[i];
                        dataBlocks.add(data.slice(currentByte, currentByte + nDataBlocks));
                        currentByte += nDataBlocks;
                    }
                    if (currentByte < data.size()) {
                        throw new Lang.SerializationException("Too much data for this code version.");
                    }
                    mProgressPayload.put(:current, 0);
                    mProgressPayload.put(:total, dataBlocks.size());
                    mProgressPayload.put(:errorInfo, errorInfo);
                    mProgressPayload.put(:dataBlocks, dataBlocks);
                    mProgressPayload.put(:errorBlocks, errorBlocks);
                } else {
                    // Calculate the error blocks
                    var dataBlocks = mProgressPayload[:dataBlocks];
                    // var errorBlocks = mProgressPayload[:errorBlocks];
                    var i = mProgressPayload[:current];
                    var block = dataBlocks[i];
                    _makeErrorBlock(block, i);
                    if (mProgressPayload[:errorBlock][:current] >= mProgressPayload[:errorBlock][:total]) {
                        mProgressPayload[:errorBlocks].add(mProgressPayload[:errorBlock][:msgPolCoeff]);
                        mProgressPayload.remove(:errorBlock);
                        mProgressPayload[:current] += 1;
                    }
                    if (mProgressPayload[:current] < mProgressPayload[:total]) {
                        return;
                    }
                }
                break;
            }

            case ADD_DATA_DATA_BLOCKS_INTO_BUFFER: {
                $.log("ADD_DATA_DATA_BLOCKS_INTO_BUFFER");
                if (!mProgressPayload.hasKey(:current)) {
                    var errorInfo = mProgressPayload[:errorInfo];
                    // Add the data blocks
                    // Write the buffer such that: block 1 byte 1, block 2 byte 1, etc.
                    var largestBlock = (errorInfo[2] < errorInfo[4] ? errorInfo[4] : errorInfo[2]) + errorInfo[0];
                    mProgressPayload[:current] = 0;
                    mProgressPayload[:total] = largestBlock;
                    mProgressPayload[:result] = "";
                } else {
                    var dataBlocks = mProgressPayload[:dataBlocks];
                    var errorBlocks = mProgressPayload[:errorBlocks];
                    var errorInfo = mProgressPayload[:errorInfo];
                    // Buffer we will write our data blocks into
                    var ib = mProgressPayload[:current];
                    for (var b = 0; b < dataBlocks.size(); b += 1) {
                        var block = dataBlocks[b];
                        if (ib < block.size()) {
                            var blockItem = block[ib];
                            if (blockItem != null) {
                                mProgressPayload[:result] += _binaryString(blockItem, 8);
                            }
                        }
                    }
                    mProgressPayload[:current] += 1;
                    if (mProgressPayload[:current] >= mProgressPayload[:total]) {
                        // Add the error code blocks.
                        // Write the buffer such that: block 1 byte 1, block 2 byte 2, etc.
                        for (var i = 0; i < errorInfo[0]; i += 1) {
                            for (var b = 0; b < errorBlocks.size(); b += 1) {
                                var block = errorBlocks[b];
                                mProgressPayload[:result] += _binaryString(block[i], 8);
                            }
                        }
                        mData = mProgressPayload[:result];
                        $.log("mData: " + mData);
                    }
                }
                break;
            }
        }
    }

    //! QR codes contain a "data length" field. This method creates this field.
    //! A binary string representing the appropriate length is returned.
    private function _dataLength() as String {
        var maxVersion = 1;
        // The "data length" field varies by the type of code and its mode.
        // discover how long the "data length" field should be.
        if (mVersion >= 1 and mVersion <= 9) {
            maxVersion = 9;
        } else if (mVersion >= 10 and mVersion <= 26) {
            maxVersion = 26;
        } else if (mVersion >= 27 and mVersion <= 40) {
            maxVersion = 40;
        }
        var dataLength = QRCodeTables.dataLengthField[maxVersion][mMode];
        var lengthStr = _binaryString(mInput.length(), dataLength);
        if (lengthStr.length() > dataLength) {
            throw new Lang.SerializationException("The supplied data will not fit within this version of a QRCode.");
        }
        return lengthStr;
    }

    //! This method encodes the QR code's data if its mode is alphanumeric.
    //! It returns the data encoded as a binary string.
    private function _encodeAlphaNumeric() as Void {
        if (mProgressPayload.isEmpty()) {
            // Change the data such that it uses a QR code ascii table;
            var ascii = [];
            var chars = mInput.toCharArray();
            for (var i = 0; i < chars.size(); i += 1) {
                ascii.add(QRCodeTables.asciiCodes[chars[i]]);
            }
            $.log("ascii(" + ascii.size() + "): " + ascii);
            // Now perform the algorithm that will make the ascii into bit fields
            var pairs = _grouped(2, ascii, null);

            mProgressPayload = { :current => 0, :total => pairs.size(), :result => "", :pairs => pairs };
        } else {
            var result = mProgressPayload[:result];
            var pairs = mProgressPayload[:pairs];
            var i = mProgressPayload[:current];
            var tuple = pairs[i];
            var a = tuple[0];
            var b = tuple[1];
            if (a != null) {
                if (b != null) {
                    result += _binaryString((45 * a) + b, 11);
                } else {
                    // This occurs when there is an odd number of characters in the data
                    result += _binaryString(a, 6);
                }
            }
            mProgressPayload[:result] = result;
            mProgressPayload[:current] += 1;
            if (mProgressPayload[:current] == mProgressPayload[:total]) {
                // Return the binary string
                mData += mProgressPayload[:result];
            }
        }
    }

    //! This method encodes the QR code's data if its mode is 8 bit mode.
    //! It returns the data encoded as a binary string.
    private function _encodeBinary() as Void {
        var chars = mInput.toCharArray();
        var result = "";
        for (var c = 0; c < chars.size(); c += 1) {
            var char = chars[c];
            result += _binaryString(char.toNumber(), 8);
        }
        mData += result;
    }

    //! This method adds zeros to the end of the encoded data so that the encoded data is of the correct length.
    //! It returns a binary string containing the bits to be added.
    private function _terminateBits(payload as String) as String? {
        var capacity = QRCodeTables.dataCapacity[mVersion][QRCodeTables.error[mError]][0];
        var payloadLength = payload.length();
        if (payloadLength > capacity) {
            throw new Lang.SerializationException("The supplied data will not fit within this version of a QRCode.");
        }
        // We must add up to 4 zeros to make up for any shortfall in the length of the data field.
        if (payloadLength == capacity) {
            return null;
        } else if (payloadLength <= capacity - 4) {
            return _binaryString(0, 4);
        } else {
            // Make up any shortfall need with less than 4 zeros
            return _binaryString(0, capacity - payloadLength);
        }
    }

    //! This method takes the existing encoded binary string
    //! and returns a binary string that will pad it such that the encoded string contains only full bytes.
    private function _delimitWords() as String? {
        var bitsShort = 8 - (mData.length() % 8).toNumber();
        // The string already falls on an byte boundary do nothing
        if (bitsShort == 0 or bitsShort == 8) {
            return null;
        }
        return _binaryString(0, bitsShort);
    }

    //! The data block must fill the entire data capacity of the QR code.
    //! If we fall short, then we must add bytes to the end of the encoded data field.
    //! The value of these bytes are specified in the standard.
    private function _addWords() as String? {
        var dataBlocks = Math.floor(mData.length() / 8).toNumber();
        var totalBlocks = Math.floor(QRCodeTables.dataCapacity[mVersion][QRCodeTables.error[mError]][0] / 8).toNumber();
        var neededBlocks = totalBlocks - dataBlocks;

        if (neededBlocks == 0) {
            return null;
        }
        // This will return item1, item2, item1, item2, etc.
        var blocks = ["11101100", "00010001"];
        var result = "";
        var b = 0;
        for (var i = 0; i < neededBlocks; i += 1) {
            if (b >= blocks.size()) {
                b = 0;
            }
            result += blocks[b];
            b += 1;
        }
        // Return a string of the needed blocks
        return result;
    }

    //! This function constructs the error correction block of the given data block.
    //! This is *very complicated* process. To understand the code you need to read:
    //! * http://www.thonky.com/qr-code-tutorial/part-2-error-correction/
    //! * http://www.matchadesign.com/blog/qr-code-demystified-part-4/
    private function _makeErrorBlock(block as NumbersOrNulls, blockNumber as Number) as Void {
        if (!mProgressPayload.hasKey(:errorBlock)) {
            // Get the error information from the standards table
            var errorInfo = QRCodeTables.eccwbi[mVersion][QRCodeTables.error[mError]];
            // This is the number of 8-bit words per block
            var codeWordsPerBlock = blockNumber < errorInfo[1] ? errorInfo[2] : errorInfo[4];
            // This is the size of the error block
            var errorBlockSize = errorInfo[0];
            // Copy the block as the message polynomial coefficients
            var msgPolCoeff = block.slice(0, null);
            // Add the error blocks to the message polynomial
            msgPolCoeff.addAll(_mult([0], errorBlockSize));
            // Get the generator polynomial
            var generator = QRCodeTables.generatorPolynomials[errorBlockSize];
            // This will hold the temporary sum of the message coefficient and the generator polynomial
            var genResult = _mult([0], generator.size());

            mProgressPayload.put(:errorBlock, { :current => 0, :total => codeWordsPerBlock, :msgPolCoeff => msgPolCoeff, :genResult => genResult, :generator => generator });
        } else {
            // Go through every code word in the block
            var i = mProgressPayload[:errorBlock][:current];
            var msgPolCoeff = mProgressPayload[:errorBlock][:msgPolCoeff];
            var genResult = mProgressPayload[:errorBlock][:genResult];
            var generator = mProgressPayload[:errorBlock][:generator];
            // Get the first coefficient from the message polynomial
            var coefficient = msgPolCoeff[0];
            mProgressPayload[:errorBlock][:msgPolCoeff] = msgPolCoeff.slice(1, null);
            msgPolCoeff = mProgressPayload[:errorBlock][:msgPolCoeff];
            // Skip coefficients that are zero
            var alphaExp;
            if (coefficient == 0 or coefficient == null) {
                alphaExp = null;
                mProgressPayload[:errorBlock][:current] += 1;
                return;
            } else {
                // Turn the coefficient into an alpha exponent
                $.log("coeff: " + coefficient + ", size: " + QRCodeTables.galoisAntilog.size());
                alphaExp = QRCodeTables.galoisAntilog[coefficient];
            }
            // Add the alpha to the generator polynomial
            for (var n = 0; n < generator.size(); n += 1) {
                genResult[n] = alphaExp + generator[n];
                if (genResult[n] > 255) {
                    genResult[n] = (genResult[n] % 255).toNumber();
                }
                // Convert the alpha notation back into coefficients
                var genResultN = QRCodeTables.galoisLog[genResult[n]];
                var msgPolCoeffN = msgPolCoeff[n];
                genResult[n] = genResultN;
                if (genResultN != null and msgPolCoeffN != null) {
                    // XOR the sum with the message coefficients
                    msgPolCoeff[n] = genResultN ^ msgPolCoeffN;
                }
            }
            mProgressPayload[:errorBlock][:current] += 1;
        }
        if (mProgressPayload[:errorBlock][:current] >= mProgressPayload[:errorBlock][:total]) {
            var msgPolCoeff = mProgressPayload[:errorBlock][:msgPolCoeff];
            var codeWordsPerBlock = mProgressPayload[:errorBlock][:total];
            // Pad the end of the error blocks with zeros if needed
            if (msgPolCoeff.size() < codeWordsPerBlock) {
                msgPolCoeff.addAll(_mult([0], (codeWordsPerBlock - msgPolCoeff.size())));
            }
            mProgressPayload[:errorBlock][:msgPolCoeff] = msgPolCoeff;
            $.log("msgPolCoeff: " + msgPolCoeff);
        }
    }

    // ***************************************************************
    // *                          MAKE CODE                          *
    // ***************************************************************

    //! This method returns the best possible QR code.
    private function _iterateMakeCode() as Void {
        switch (mProgress) {
            case MAKE_CODE_ADD_PATTERNS: {
                $.log("MAKE_CODE_ADD_PATTERNS");
                // Get the size of the underlying matrix
                var matrixSize = QRCodeTables.versionSize[mVersion];
                // Create a template matrix we will build the codes with
                var template as CodeData = [];
                for (var i = 0; i < matrixSize; i += 1) {
                    var row as CodeBlock = [];
                    for (var j = 0; j < matrixSize; j += 1) {
                        row.add(' ');
                    }
                    template.add(row);
                }
                // Add mandatory information to the template
                _addDetectionPattern(template);
                _addPositionPattern(template);
                _addVersionPattern(template);

                $.log("template: " + template);
                mProgressPayload = { :template => template };
                break;
            }

            case MAKE_CODE_MAKE_MASKS: {
                $.log("MAKE_CODE_MAKE_MASKS");
                // Create the various types of masks of the template
                _makeMasks();
                break;
            }

            case MAKE_CODE_CHOOSE_BEST_MASK: {
                if (mProgressPayload.hasKey(:template)) {
                    mProgressPayload = {};
                }
                $.log("MAKE_CODE_CHOOSE_BEST_MASK");
                if (mInput.length() > QRCodeSettings.criticalInputSize()) {
                    mMaskIdx = 0;
                } else {
                    _chooseBestMask();
                }
                break;
            }
        }
    }

    //! This method add the detection patterns to the QR code. This lets the scanner orient the pattern.
    //! It is required for all QR codes.
    //! The detection pattern consists of three boxes located at the upper left, upper right, and lower left corners of the matrix.
    //! Also, two special lines called the timing pattern is also necessary.
    //! Finally, a single black pixel is added just above the lower left black box.
    private function _addDetectionPattern(m as CodeData) as Void {
        var mSize = m.size();
        // Draw outer black box
        for (var i = 0; i < 7; i += 1) {
            var inv = - (i + 1);
            var xs = [0, 6, - 1, - 7];

            for (var x = 0; x < xs.size(); x += 1) {
                var j = xs[x];
                m[_fix(j, mSize)][_fix(i, mSize)] = '1';
                m[_fix(i, mSize)][_fix(j, mSize)] = '1';
                m[_fix(inv, mSize)][_fix(j, mSize)] = '1';
                m[_fix(j, mSize)][_fix(inv, mSize)] = '1';
            }
        }
        // Draw inner white box
        for (var i = 1; i < 6; i += 1) {
            var inv = - (i + 1);
            var xs = [1, 5, -2, -6];

            for (var x = 0; x < xs.size(); x += 1) {
                var j = xs[x];
                m[_fix(j, mSize)][_fix(i, mSize)] = '0';
                m[_fix(i, mSize)][_fix(j, mSize)] = '0';
                m[_fix(inv, mSize)][_fix(j, mSize)] = '0';
                m[_fix(j, mSize)][_fix(inv, mSize)] = '0';
            }
        }
        // Draw inner black box
        for (var i = 2; i < 5; i += 1) {
            var inv = - (i + 1);

            for (var j = 2; j < 5; j += 1) {
                m[_fix(i, mSize)][_fix(j, mSize)] = '1';
                m[_fix(inv, mSize)][_fix(j, mSize)] = '1';
                m[_fix(j, mSize)][_fix(inv, mSize)] = '1';
            }
        }
        // Draw white border
        for (var i = 0; i < 8; i += 1) {
            var inv = - (i + 1);
            var xs = [7, - 8];

            for (var x = 0; x < xs.size(); x += 1) {
                var j = xs[x];
                m[_fix(i, mSize)][_fix(j, mSize)] = '0';
                m[_fix(j, mSize)][_fix(i, mSize)] = '0';
                m[_fix(inv, mSize)][_fix(j, mSize)] = '0';
                m[_fix(j, mSize)][_fix(inv, mSize)] = '0';
            }
        }
        // To keep the code short, it draws an extra box in the lower right corner, this removes it.
        for (var i = mSize - 8; i < mSize; i += 1) {
            for (var j = mSize - 8; j < mSize; j += 1) {
                m[i][j] = ' ';
            }
        }
        // Add the timing pattern
        var c = 0;
        var cs = ['1', '0'];
        for (var i = 8; i < mSize - 8; i += 1) {
            if (c >= cs.size()) {
                c = 0;
            }
            var b = cs[c];
            c += 1;
            m[i][6] = b;
            m[6][i] = b;
        }
        // Add the extra black pixel
        m[mSize - 8][8] = '1';
    }

    //! This method draws the position adjustment patterns onto the QR Code.
    //! All QR code versions larger than one require these special boxes called position adjustment patterns.
    private function _addPositionPattern(m as CodeData) as Void {
        // Version 1 does not have a position adjustment pattern
        if (mVersion == 1) {
            return;
        }
        // Get the coordinates for where to place the boxes
        var coordinates = QRCodeTables.positionAdjustment[mVersion];
        // Get the max and min coordinates to handle special cases
        var minCoord = coordinates[0];
        var maxCoord = coordinates[coordinates.size() - 1];

        // Draw a box at each intersection of the coordinates
        var mSize = m.size();
        for (var a = 0; a < coordinates.size(); a += 1) {
            var i = coordinates[a];
            for (var b = 0; b < coordinates.size(); b += 1) {
                var j = coordinates[b];
                // Do not draw these boxes because they would interfere with the detection pattern
                if ((i == minCoord and j == minCoord) or (i == minCoord and j == maxCoord) or (i == maxCoord and j == minCoord)) {
                    continue;
                }
                // Center black pixel
                m[i][j] = '1';

                // Surround the pixel with a white box
                var wps = [-1, 1];
                for (var wp = 0; wp < wps.size(); wp +=1) {
                    var x = wps[wp];
                    m[i+x][j+x] = '0';
                    m[i+x][j] = '0';
                    m[i][j+x] = '0';
                    m[i-x][j+x] = '0';
                    m[i+x][j-x] = '0';
                }
                // Surround the white box with a black box
                var xbps = [-2,2];
                var ybps = [0,-1,1];
                for (var xbp = 0; xbp < xbps.size(); xbp += 1) {
                    var x = xbps[xbp];
                    for (var ybp = 0; ybp < ybps.size(); ybp += 1) {
                        var y = ybps[ybp];
                        m[i+x][j+x] = '1';
                        m[i+x][j+y] = '1';
                        m[i+y][j+x] = '1';
                        m[i-x][j+x] = '1';
                        m[i+x][j-x] = '1';
                    }
                }
            }
        }
    }

    //! For QR codes with a version 7 or higher, a special pattern specifying the code's version is required.
    //! For further information see:
    //! http://www.thonky.com/qr-code-tutorial/format-version-information/#example-of-version-7-information-string
    private function _addVersionPattern(m as CodeData) as Void {
        if (mVersion < 7) {
            return;
        }
        // Get the bit fields for this code's version
        // We will iterate across the string, the bit string needs the least significant digit in the zero-th position
        var field = QRCodeTables.versionPattern[mVersion].toCharArray().reverse();
        var fi = 0;
        // Where to start placing the pattern
        var start = m.size() - 11;
        // The version pattern is pretty odd looking
        for (var i = 0; i < 6; i += 1) {
            // The pattern is three modules wide
            for (var j = start; j < start + 3; j += 1) {
                var bit = field[fi];
                fi += 1;
                // Bottom Left
                m[i][j] = bit;
                // Upper right
                m[j][i] = bit;
            }
        }
    }

    //! This method generates all seven masks so that the best mask can be determined.
    //! The template parameter is a code matrix that will server as the base for all the generated masks.
    private function _makeMasks() as Void {
        if (!mProgressPayload.hasKey(:current)) {
            var nmasks = mInput.length() > QRCodeSettings.criticalInputSize() ? 1 : QRCodeTables.maskPatterns.size();
            var masks = new [nmasks];

            mProgressPayload.put(:current, 0);
            mProgressPayload.put(:total, masks.size());
            mProgressPayload.put(:masks, masks);
            mProgressPayload.put(:bits, mData.toCharArray());
            return;
        } else {
            var n = mProgressPayload[:current];

            if (!mProgressPayload.hasKey(:inside)) {
                var template = mProgressPayload[:template];

                var curMask as CodeData = [];
                for (var r = 0; r < template.size(); r += 1) {
                    curMask.add(template[r].slice(0, null));
                }
                // Add the type pattern bits to the code
                _addTypePattern(curMask, QRCodeTables.typeBits[QRCodeTables.error[mError]][n].toCharArray());

                mProgressPayload[:masks][n] = curMask;
                mProgressPayload.put(:inside, { :current => curMask.size() - 1, :total => 0, :b => 0, :mv => 0 });

                return;
            } else {
                var b = mProgressPayload[:inside][:b];
                var column = mProgressPayload[:inside][:current];
                var curMask = mProgressPayload[:masks][n];
                // This will read the 1's and 0's one at a time
                var bits = mProgressPayload[:bits];
                // Get the mask pattern
                var pattern = QRCodeTables.maskPatterns[n];
                // These will help us do the up, down, up, down pattern
                var rowStart = [curMask.size() - 1, 0];
                var rowStop = [-1, curMask.size()];
                var direction = [-1, 1];
                var mv = mProgressPayload[:inside][:mv];

                // The data pattern is added using pairs of columns
                // The vertical timing pattern is an exception to the rules, move the column counter over by one
                if (column == 6) {
                    mProgressPayload[:inside][:current] -= 1;
                    column = mProgressPayload[:inside][:current];
                }
                // This will let us fill in the pattern right-left, right-left, etc.
                var columnPair = [column, column - 1];
                // Go through each row in the pattern moving up, then down
                if (mv >= direction.size()) {
                    mProgressPayload[:inside][:mv] = 0;
                    mv = mProgressPayload[:inside][:mv];
                }
                var rStart = rowStart[mv];
                var rStop = rowStop[mv];
                var dir = direction[mv];
                mProgressPayload[:inside][:mv] += 1;
                mv = mProgressPayload[:inside][:mv];

                for (var row = rStart; (dir > 0 ? row < rStop : row > rStop); row += dir) {
                    // Fill in the right then left column
                    for (var i = 0; i < columnPair.size(); i += 1) {
                        var col = columnPair[i];
                        // Go to the next column if we encounter a preexisting pattern (usually an alignment pattern)
                        if (curMask[row][col] != ' ') {
                            continue;
                        }
                        // Some versions don't have enough bits. You then fill in the rest of the pattern with 0's.
                        // These are called "remainder bits."
                        var bit = b < bits.size() ? bits[b] : '0';
                        bit = bit.toString().toNumber();
                        if (bit == null) {
                            bit = 0;
                        }
                        b += 1;
                        // If the pattern is True then flip the bit
                        curMask[row][col] = (pattern.invoke(row, col) ? (bit ^ 1) : bit).toString().toCharArray()[0];
                    }
                }

                mProgressPayload[:inside][:b] = b;
                mProgressPayload[:inside][:current] -= 2;
                if (mProgressPayload[:inside][:current] > mProgressPayload[:inside][:total]) {
                    return;
                }
            }
            $.log("mask (" + n + "): " + mProgressPayload[:masks][n]);
            mProgressPayload[:current] += 1;
            mProgressPayload.remove(:inside);
            if (mProgressPayload[:current] == mProgressPayload[:total]) {
                mMasks = mProgressPayload[:masks];
            }
        }
    }

    //! This will add the pattern to the QR code that represents the error level and the type of mask used to make the code.
    private function _addTypePattern(m as CodeData, typeBits as CodeBlock) {
        var mSize = m.size();
        var b = 0;
        for (var i = 0; i < 7; i += 1) {
            var bit = typeBits[b];
            b += 1;
            // Skip the timing bits
            if (i < 6) {
                m[8][i] = bit;
            } else {
                m[8][i+1] = bit;
            }
            if (-8 < -(i + 1)) {
                m[_fix(-(i + 1), mSize)][8] = bit;
            }
        }
        for (var i = -8; i < 0; i += 1) {
            var bit = typeBits[b];
            b += 1;

            m[8][_fix(i, mSize)] = bit;

            var j = -i;
            // Skip timing column
            if (j > 6) {
                m[j][8] = bit;
            } else {
                m[_fix(j-1, mSize)][8] = bit;
            }
        }
    }

    //! This method returns the index of the "best" mask as defined by having the lowest total penalty score.
    //! The penalty rules are defined by the standard.
    //! The mask with the lowest total score should be the easiest to read by optical scanners.
    private function __chooseBestMask() as Void {
        if (mProgressPayload.isEmpty()) {
            var scores = [];
            for (var i = 0; i < mMasks.size(); i += 1) {
                scores.add([0, 0, 0, 0]);
            }
            mProgressPayload = { :current => 0, :total => 5, :scores => scores };
        } else {
            var scores = mProgressPayload[:scores];
            switch (mProgressPayload[:current]) {
                case 0: {
                    // Score penalty rule number 1
                    // Look for five consecutive squares with the same color.
                    // Each one found gets a penalty of 3 + 1 for every
                    // same color square after the first five in the row.
                    if (!mProgressPayload.hasKey(:step1)) {
                        mProgressPayload.put(:step1, { :current => 0, :total => mMasks.size() });
                        return;
                    } else {
                        var n = mProgressPayload[:step1][:current];
                        var mask = mMasks[n];
                        var current = mask[0][0];
                        var counter = 0;
                        var total = 0;

                        // Examine the mask row wise
                        for (var row = 0; row < mask.size(); row += 1) {
                            counter = 0;
                            for (var col = 0; col < mask.size(); col += 1) {
                                var bit = mask[row][col];
                                if (bit == current) {
                                    counter += 1;
                                } else {
                                    if (counter >= 5) {
                                        total += (counter - 5) + 3;
                                    }
                                    counter = 1;
                                    current = bit;
                                }
                            }
                            if (counter >= 5) {
                                total += (counter - 5) + 3;
                            }
                        }
                        // Examine the mask column wise
                        for (var col = 0; col < mask.size(); col += 1) {
                            counter = 0;
                            for (var row = 0; row < mask.size(); row += 1) {
                                var bit = mask[row][col];
                                if (bit == current) {
                                    counter += 1;
                                } else {
                                    if (counter >= 5) {
                                        total += (counter - 5) + 3;
                                    }
                                    counter = 1;
                                    current = bit;
                                }
                            }
                            if (counter >= 5) {
                                total += (counter - 5) + 3;
                            }
                        }
                        scores[n][0] = total;
                        $.log("score [" + n + "][0] = " + total);
                        mProgressPayload[:step1][:current] += 1;
                        if (mProgressPayload[:step1][:current] < mProgressPayload[:step1][:total]) {
                            return;
                        }
                    }
                    break;
                }

                case 1: {
                    // Score penalty rule 2
                    // This rule will add 3 to the score for each 2x2 block of the same colored pixels there are.
                    if (!mProgressPayload.hasKey(:step2)) {
                        mProgressPayload.put(:step2, { :current => 0, :total => mMasks.size() });
                        return;
                    } else {
                        var n = mProgressPayload[:step2][:current];
                        var mask = mMasks[n];
                        var count = 0;
                        // Don't examine the 0th and Nth row/column
                        for (var i = 0; i < mask.size()-1; i += 1) {
                            for (var j = 0; j < mask.size()-1; j += 1) {
                                if (mask[i][j] == mask[i+1][j] and mask[i][j] == mask[i][j+1] and mask[i][j] == mask[i+1][j+1]) {
                                    count += 1;
                                }
                            }
                        }
                        scores[n][1] = count * 3;
                        $.log("score [" + n + "][1] = " + scores[n][1]);
                        mProgressPayload[:step2][:current] += 1;
                        if (mProgressPayload[:step2][:current] < mProgressPayload[:step2][:total]) {
                            return;
                        }
                    }
                    break;
                }

                case 2: {
                    if (!mProgressPayload.hasKey(:step3)) {
                        // Score penalty rule 3
                        // This rule looks for 1011101 within the mask prefixed and/or suffixed by four zeros.
                        var patterns = [
                            ['0','0','0','0','1','0','1','1','1','0','1'],
                            ['1','0','1','1','1','0','1','0','0','0','0'],
                            //['0','0','0','0','1','0','1','1','1','0','1','0','0','0','0']
                        ];
                        mProgressPayload.put(:step3, { :current => 0, :total => mMasks.size(), :patterns => patterns });
                        return;
                    } else {
                        var patterns = mProgressPayload[:step3][:patterns];
                        var n = mProgressPayload[:step3][:current];
                        var mask = mMasks[n];

                        if (!mProgressPayload[:step3].hasKey(:step1)) {
                            mProgressPayload[:step3].put(:step1, { :current => 0, :total => mask.size(), :nmatches => 0 });
                            return;
                        } else {
                            var nmatches = mProgressPayload[:step3][:step1][:nmatches];
                            var i = mProgressPayload[:step3][:step1][:current];
                            for (var j = 0; j < mask.size(); j += 1) {
                                for (var pi = 0; pi < patterns.size(); pi += 1) {
                                    var pattern = patterns[pi];
                                    var match = true;
                                    var k = j;
                                    // Look for row matches
                                    for (var ppi = 0; ppi < pattern.size(); ppi += 1) {
                                        var p = pattern[ppi];
                                        if (k >= mask.size() or mask[i][k] != p) {
                                            match = false;
                                            break;
                                        }
                                        k += 1;
                                    }
                                    if (match) {
                                        nmatches += 1;
                                    }

                                    match = true;
                                    k = j;
                                    // Look for column matches
                                    for (var ppi = 0; ppi < pattern.size(); ppi += 1) {
                                        var p = pattern[ppi];
                                        if (k >= mask.size() or mask[k][i] != p) {
                                            match = false;
                                            break;
                                        }
                                        k += 1;
                                    }
                                    if (match) {
                                        nmatches += 1;
                                    }
                                }
                            }
                            mProgressPayload[:step3][:step1][:nmatches] = nmatches;
                            mProgressPayload[:step3][:step1][:current] += 1;
                            if (mProgressPayload[:step3][:step1][:current] < mProgressPayload[:step3][:step1][:total] - 1) {
                                return;
                            }
                        }
                        var nmatches = mProgressPayload[:step3][:step1][:nmatches];
                        scores[n][2] = nmatches * 40;
                        $.log("score [" + n + "][2] = " + scores[n][2]);

                        mProgressPayload[:step3][:current] += 1;
                        mProgressPayload[:step3].remove(:step1);
                        if (mProgressPayload[:step3][:current] < mProgressPayload[:step3][:total]) {
                            return;
                        }
                    }
                    break;
                }

                case 3: {
                    if (!mProgressPayload.hasKey(:step4)) {
                        mProgressPayload.put(:step4, { :current => 0, :total => mMasks.size() });
                        return;
                    } else {
                        var n = mProgressPayload[:step4][:current];
                        // Score the last rule, penalty rule 4. This rule measures how close the pattern is to being 50% black.
                        // The further it deviates from this this ideal the higher the penalty.
                        var mask = mMasks[n];
                        var nblack = 0;

                        for (var i = 0; i < mask.size(); i += 1) {
                            var row = mask[i];
                            nblack += _sum(row);
                        }
                        var totalPixels = Math.pow(mask.size(), 2);
                        var ratio = nblack / totalPixels;
                        var percent = ((ratio * 100) - 50).abs();
                        scores[n][3] = ((Math.floor(percent) / 5) * 10).toNumber();
                        $.log("score [" + n + "][3] = " + scores[n][3]);

                        mProgressPayload[:step4][:current] += 1;
                        if (mProgressPayload[:step4][:current] < mProgressPayload[:step4][:total]) {
                            return;
                        }
                    }
                    break;
                }

                case 4: {
                    $.log("scores: " + scores);
                    // Calculate the total for each score
                    var totals = _mult([0], scores.size());
                    for (var i = 0; i < scores.size(); i += 1) {
                        for (var j = 0; j < scores[i].size(); j += 1) {
                            totals[i] += scores[i][j];
                        }
                    }
                    $.log("totals: " + totals);
                    // The lowest total wins
                    var minIdx = 0;
                    for (var i = 0; i < totals.size(); i += 1) {
                        if (totals[i] < totals[minIdx]) {
                            minIdx = i;
                        }
                    }
                    mMaskIdx = minIdx;
                    $.log("mMaskIdx: " + mMaskIdx);
                    break;
                }
            }
            mProgressPayload[:current] += 1;
        }
    }

    private function _chooseBestMask() as Void {
        if (mProgressPayload.isEmpty()) {
            var scores = [];
            for (var i = 0; i < mMasks.size(); i += 1) {
                scores.add([0, 0, 0, 0]);
            }
            mProgressPayload = { :current => 0, :total => 2, :scores => scores };
        } else {
            var scores = mProgressPayload[:scores];
            switch (mProgressPayload[:current]) {
                case 0: {
                    if (!mProgressPayload.hasKey(:inner)) {
                        mProgressPayload.put(:inner, { :current => 0, :total => mMasks.size(), :nblack => 0 });
                        return;
                    } else {
                        var n = mProgressPayload[:inner][:current];
                        var mask = mMasks[n];
                        if (!mProgressPayload[:inner].hasKey(:sub)) {
                            mProgressPayload[:inner].put(:sub, {
                                :current => 0,
                                :total => mask.size(),
                                :current1 => mask[0][0],
                                :current2 => mask[0][0],
                                :total1 => 0,
                                :count => 0,
                                :nmatches => 0
                            });
                            return;
                        } else {
                            var i = mProgressPayload[:inner][:sub][:current];

                            // 1 <<<<<<
                            var current1 = mProgressPayload[:inner][:sub][:current1];
                            var current2 = mProgressPayload[:inner][:sub][:current2];
                            var total = mProgressPayload[:inner][:sub][:total1];
                            // 1 >>>>>>

                            // 2 <<<<<<
                            var count = mProgressPayload[:inner][:sub][:count];
                            // 2 >>>>>>

                            // 3 <<<<<<
                            var nmatches = mProgressPayload[:inner][:sub][:nmatches];
                            var patterns = [
                                ['0','0','0','0','1','0','1','1','1','0','1'],
                                ['1','0','1','1','1','0','1','0','0','0','0'],
                                //['0','0','0','0','1','0','1','1','1','0','1','0','0','0','0']
                            ];
                            // 3 >>>>>>

                            var counter1 = 0;
                            for (var j = 0; j < mask.size(); j += 1) {

                                // 1 <<<<<<
                                var bit1 = mask[i][j];
                                if (bit1 == current1) {
                                    counter1 += 1;
                                } else {
                                    if (counter1 >= 5) {
                                        total += (counter1 - 5) + 3;
                                    }
                                    counter1 = 1;
                                    current1 = bit1;
                                }

                                if (i == 0) {
                                    var counter2 = 0;
                                    for (var i2 = 0; i2 < mask.size(); i2 += 1) {
                                        var bit2 = mask[i2][j];
                                        if (bit2 == current2) {
                                            counter2 += 1;
                                        } else {
                                            if (counter2 >= 5) {
                                                total += (counter2 - 5) + 3;
                                            }
                                            counter2 = 1;
                                            current2 = bit2;
                                        }
                                    }
                                    if (counter2 >= 5) {
                                        total += (counter2 - 5) + 3;
                                    }
                                }
                                // 1 >>>>>>

                                // 2 <<<<<<
                                if (i < mask.size()-1 and j < mask.size()-1) {
                                    if (mask[i][j] == mask[i+1][j] and mask[i][j] == mask[i][j+1] and mask[i][j] == mask[i+1][j+1]) {
                                        count += 1;
                                    }
                                }
                                // 2 >>>>>>

                                // 3 <<<<<<
                                for (var pi = 0; pi < patterns.size(); pi += 1) {
                                    var pattern = patterns[pi];
                                    var match = true;
                                    var k = j;
                                    // Look for row matches
                                    for (var ppi = 0; ppi < pattern.size(); ppi += 1) {
                                        var p = pattern[ppi];
                                        if (k >= mask.size() or mask[i][k] != p) {
                                            match = false;
                                            break;
                                        }
                                        k += 1;
                                    }
                                    if (match) {
                                        nmatches += 1;
                                    }
                                    match = true;
                                    k = j;
                                    // Look for column matches
                                    for (var ppi = 0; ppi < pattern.size(); ppi += 1) {
                                        var p = pattern[ppi];
                                        if (k >= mask.size() or mask[k][i] != p) {
                                            match = false;
                                            break;
                                        }
                                        k += 1;
                                    }
                                    if (match) {
                                        nmatches += 1;
                                    }
                                }
                                // 3 >>>>>>

                                // 4 <<<<<<
                                var num = mask[i][j].toString().toNumber();
                                if (num != null) {
                                    mProgressPayload[:inner][:nblack] += num;
                                }
                                // 4 >>>>>>
                            }
                            if (counter1 >= 5) {
                                total += (counter1 - 5) + 3;
                            }

                            mProgressPayload[:inner][:sub][:total1] = total;
                            mProgressPayload[:inner][:sub][:count] = count;
                            mProgressPayload[:inner][:sub][:nmatches] = nmatches;
                            mProgressPayload[:inner][:sub][:current1] = current1;
                            mProgressPayload[:inner][:sub][:current2] = current2;

                            mProgressPayload[:inner][:sub][:current] += 1;
                            if (mProgressPayload[:inner][:sub][:current] < mProgressPayload[:inner][:sub][:total]) {
                                return;
                            }
                        }

                        // 1 <<<<<<
                        scores[n][0] = mProgressPayload[:inner][:sub][:total1];
                        // 1 >>>>>>

                        // 2 <<<<<<
                        scores[n][1] = mProgressPayload[:inner][:sub][:count] * 3;
                        // 2 >>>>>>

                        // 3 <<<<<<
                        scores[n][2] = mProgressPayload[:inner][:sub][:nmatches] * 40;
                        // 3 >>>>>>

                        // 4 <<<<<<
                        var totalPixels = Math.pow(mask.size(), 2);
                        var ratio = mProgressPayload[:inner][:nblack] / totalPixels;
                        var percent = ((ratio * 100) - 50).abs();
                        scores[n][3] = ((Math.floor(percent) / 5) * 10).toNumber();
                        // 4 >>>>>>

                        mProgressPayload[:inner][:current] += 1;
                        mProgressPayload[:inner][:nblack] = 0;
                        mProgressPayload[:inner].remove(:sub);
                        if (mProgressPayload[:inner][:current] < mProgressPayload[:inner][:total]) {
                            return;
                        }
                    }
                    break;
                }

                case 1: {
                    $.log("scores: " + scores);
                    // Calculate the total for each score
                    var totals = _mult([0], scores.size());
                    for (var i = 0; i < scores.size(); i += 1) {
                        for (var j = 0; j < scores[i].size(); j += 1) {
                            totals[i] += scores[i][j];
                        }
                    }
                    $.log("totals: " + totals);
                    // The lowest total wins
                    var minIdx = 0;
                    for (var i = 0; i < totals.size(); i += 1) {
                        if (totals[i] < totals[minIdx]) {
                            minIdx = i;
                        }
                    }
                    mMaskIdx = minIdx;
                    $.log("mMaskIdx: " + mMaskIdx);
                    break;
                }
            }
            mProgressPayload[:current] += 1;
        }
    }

    // ***************************************************************
    // *                           UTILS                             *
    // ***************************************************************

    //! This method returns a string of length n that is the binary representation of the given data.
    //! This function is used to basically create bit fields of a given size.
    private function _binaryString(value as Number, length as Number) as String {
        var binValue = 0;
        var exp = 0;
        while (value != 0) {
            binValue += ((value % 2).toNumber() * Math.pow(10, exp)).toLong();
            value = (value / 2).toLong();
            exp += 1;
        }
        return binValue.toLong().format(Lang.format("%0$1$d", [length]));
    }

    //! This generator yields a set of tuples, where the iterable is broken into n sized chunks.
    //! If the iterable is not evenly sized then fillvalue will be appended to the last tuple to make up the difference.
    private function _grouped(chunkSize as Number, items as Array, fillValue as Any?) as Array {
        var itemsSize = items.size();
        var result = [];
        for (var i = 0; i < items.size(); i += chunkSize) {
            var chunk = [];
            for (var c = 0; c < chunkSize; c += 1) {
                if ((i + c) < itemsSize) {
                    chunk.add(items[i + c]);
                } else {
                    chunk.add(fillValue);
                }
            }
            result.add(chunk);
        }
        return result;
    }

    //! This method return the smallest possible QR code version number
    //! that will fit the specified data with the given error level.
    private function _bestVersion() as Number {
        for (var version = 1; version < 41; version += 1) {
            // Get the maximum possible capacity
            var capacity = QRCodeTables.dataCapacity[version][QRCodeTables.error[mError]][mMode];
            if (capacity >= mInput.length()) {
                return version;
            }
        }
        return 40;
    }

    private function _mult(items as Array, times as Number) as Array {
        var result = [];
        for (var i = 0; i < times; i += 1) {
            result.addAll(items);
        }
        return result;
    }

    private function _fix(index as Number, mSize as Number) as Number {
        if (index < 0) {
            return mSize + index;
        }
        return index;
    }

    private function _sum(row as Array<Char>) as Number {
        var sum = 0;
        for (var i = 0; i < row.size(); i += 1) {
            var num = row[i].toString().toNumber();
            if (num != null) {
                sum += num;
            }
        }
        return sum;
    }
}
