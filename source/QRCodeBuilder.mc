import Toybox.Lang;
import Toybox.Timer;

class QRCodeBuilder {
    enum Status {
        // Associates with null payload
        IDLE, STOPPED,
        // Associates with Float (0-100) payload
        STARTED_BUILDING_DATA,
        STARTED_BUILDING_CODE,
        STARTED_PICKING_MASK,
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

    typedef Numbers as Array<Number>;
    typedef NumbersOrNulls as Array<Number?>;

    typedef CodeBlock as Array<Char>;
    typedef CodeData as Array<CodeBlock>;
    typedef CodeMasks as Array<CodeData>;
    typedef Result as CodeData or Error;

    private const mMode as Mode = ALPHANUMERIC;

    private var mInput as String;
    private var mError as QRError;
    private var mVersion as Number;

    private var mObservable as Observable;
    private var mTimer as Timer?;
    private var mIteration as Numer;

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
    }

    public function getStatus() as Status {
        return mStatus;
    }

    public function getResult() as Float or Result or Null {
        switch (mStatus) {
            case IDLE:
                return null;
            case STARTED_BUILDING_DATA:
            case STARTED_BUILDING_CODE:
            case STARTED_PICKING_MASK:
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
        try {
            _addData();
        } catch (e instanceof Lang.SerializationException) {
            _finish(INVALID_INPUT);
            return null; // ???
        } catch (e) {
            _finish(UNKNOWN);
            return null; // ???
        }
        _makeCode();
        return null;
    }

    public function stop() as Void {
        if (mTimer == null) {
            return;
        }
        System.println("builder stopped");
        mTimer.stop();
        mTimer = null;
        mStatus = STOPPED;
        mIteration = 0;

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
        System.println("builder finished");
        mTimer.stop();
        mStatus = FINISHED;
        mStatusError = error;

        mObservable.notify({ :status => getStatus(), :payload => getResult() });
    }

    private function _progress() as Float {
        return 42;//(mIteration.toFloat() / Math.ceil(mInput.size() / 4)) * 100;
    }

    // ***************************************************************
    // *                          ADD DATA                           *
    // ***************************************************************

    //! This function properly constructs a QR code's data string.
    //! It takes into account the interleaving pattern required by the standard.
    private function _addData() as Void {
        // Encode the data into a QR code
        mData += _binaryString(mMode, 4);
        mData += _dataLength();
        mData += _encodeAlphaNumeric();
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
        // Get a numeric representation of the data
        var data as Numbers = [];
        var chunks as Array<CodeBlock> = _grouped(8, mData.toCharArray(), null);
        for (var i = 0; i < chunks.size(); i += 1) {
            var chunk = chunks[i];
            var string = "";
            for (var c = 0; c < chunk.size(); c += 1) {
                string += chunk[c].toString();
            }
            data.add(string.toNumberWithBase(2));
        }
        // This is the error information for the code
        var errorInfo as Numbers = QRCodeTables.eccwbi[mVersion][QRCodeTables.error[mError]];
        // This will hold our data blocks
        var dataBlocks as Array<NumbersOrNulls> = [];
        // This will hold our error blocks
        var errorBlocks as Array<Numbers> = [];
        // Some codes have the data sliced into two different sized blocks
        // for example, first two 14 word sized blocks, then four 15 word sized blocks.
        // This means that slicing size can change over time.
        var dataBlockSizes as Numbers = [];
        for (var i = 0; i < errorInfo[1]; i += 1) {
            dataBlockSizes.add(errorInfo[2]);
        }
        if (errorInfo[3] != 0) {
            for (var i = 0; i < errorInfo[3]; i += 1) {
                dataBlockSizes.add(errorInfo[4]);
            }
        }
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
        // Calculate the error blocks
        for (var i = 0; i < dataBlocks.size(); i += 1) {
            var block = dataBlocks[i];
            errorBlocks.add(_makeErrorBlock(block, i));
        }
        // Buffer we will write our data blocks into
        var result = "";
        // Add the data blocks
        // Write the buffer such that: block 1 byte 1, block 2 byte 1, etc.
        var largestBlock = (errorInfo[2] < errorInfo[4] ? errorInfo[4] : errorInfo[2]) + errorInfo[0];
        for (var i = 0; i < largestBlock; i += 1) {
            for (var b = 0; b < dataBlocks.size(); b += 1) {
                var block = dataBlocks[b];
                if (i < block.size()) {
                    var blockItem = block[i];
                    if (blockItem != null) {
                        result += _binaryString(blockItem, 8);
                    }
                }
            }
        }
        // Add the error code blocks.
        // Write the buffer such that: block 1 byte 1, block 2 byte 2, etc.
        for (var i = 0; i < errorInfo[0]; i += 1) {
            for (var b = 0; b < errorBlocks.size(); b += 1) {
                var block = errorBlocks[b];
                result += _binaryString(block[i], 8);
            }
        }
        mData = result;
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
    private function _encodeAlphaNumeric() as String {
        // Change the data such that it uses a QR code ascii table
        var ascii = [];
        var chars = mInput.toCharArray();
        for (var i = 0; i < chars.size(); i += 1) {
            ascii.add(QRCodeTables.asciiCodes[chars[i]]);
        }
        // Now perform the algorithm that will make the ascii into bit fields
        var pairs = _grouped(2, ascii, null);
        var result = "";
        for (var i = 0; i < pairs.size(); i += 1) {
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
        }
        // Return the binary string
        return result;
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
    private function _makeErrorBlock(block as NumbersOrNulls, blockNumber as Number) as NumbersOrNulls {
        // Get the error information from the standards table
        var errorInfo = QRCodeTables.eccwbi[mVersion][QRCodeTables.error[mError]];
        // This is the number of 8-bit words per block
        var codeWordsPerBlock;
        if (blockNumber < errorInfo[1]) {
            codeWordsPerBlock = errorInfo[2];
        } else {
            codeWordsPerBlock = errorInfo[4];
        }
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
        // Go through every code word in the block
        for (var i = 0; i < codeWordsPerBlock; i += 1) {
            // Get the first coefficient from the message polynomial
            var coefficient = msgPolCoeff[0];
            msgPolCoeff = msgPolCoeff.slice(1, null);
            // Skip coefficients that are zero
            var alphaExp;
            if (coefficient == 0 or coefficient == null) {
                alphaExp = null;
                continue;
            } else {
                // Turn the coefficient into an alpha exponent
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
        }
        // Pad the end of the error blocks with zeros if needed
        if (msgPolCoeff.size() < codeWordsPerBlock) {
            msgPolCoeff.addAll(_mult([0], (codeWordsPerBlock - msgPolCoeff.size())));
        }
        return msgPolCoeff;
    }

    // ***************************************************************
    // *                          MAKE CODE                          *
    // ***************************************************************

    //! This method returns the best possible QR code.
    private function _makeCode() as Array<Array> {
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

        // Create the various types of masks of the template
        mMasks = _makeMasks(template);
        mMaskIdx = _chooseBestMask();
        return mMasks[mMaskIdx];
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
            var inv = mSize - (i + 1);
            var xs = [0, 6, mSize - 1, mSize - 7];

            for (var x = 0; x < xs.size(); x += 1) {
                var j = xs[x];
                m[j][i] = '1';
                m[i][j] = '1';
                m[inv][j] = '1';
                m[j][inv] = '1';
            }
        }
        // Draw inner white box
        for (var i = 1; i < 6; i += 1) {
            var inv = mSize - (i + 1);
            var xs = [1, 5, mSize -2, mSize -6];

            for (var x = 0; x < xs.size(); x += 1) {
                var j = xs[x];
                m[j][i] = '0';
                m[i][j] = '0';
                m[inv][j] = '0';
                m[j][inv] = '0';
            }
        }
        // Draw inner black box
        for (var i = 2; i < 5; i += 1) {
            var inv = mSize - (i + 1);

            for (var j = 2; j < 5; j += 1) {
                m[i][j] = '1';
                m[inv][j] = '1';
                m[j][inv] = '1';
            }
        }
        // Draw white border
        for (var i = 0; i < 8; i += 1) {
            var inv = mSize - (i + 1);
            var xs = [7, mSize - 8];

            for (var x = 0; x < xs.size(); x += 1) {
                var j = xs[x];
                m[i][j] = '0';
                m[j][i] = '0';
                m[inv][j] = '0';
                m[j][inv] = '0';
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
                    m[_fix(i+x, mSize)][_fix(j+x, mSize)] = '0';
                    m[_fix(i+x, mSize)][j] = '0';
                    m[i][j+x] = '0';
                    m[_fix(i-x, mSize)][_fix(j+x, mSize)] = '0';
                    m[_fix(i+x, mSize)][_fix(j-x, mSize)] = '0';
                }
                // Surround the white box with a black box
                var xbps = [-2,2];
                var ybps = [-2,2];
                for (var xbp = 0; xbp < xbps.size(); xbp += 1) {
                    var x = xbps[xbp];
                    for (var ybp = 0; ybp < ybps.size(); ybp += 1) {
                        var y = ybps[ybp];
                        m[_fix(i+x, mSize)][_fix(j+x, mSize)] = '1';
                        m[_fix(i+x, mSize)][_fix(j+y, mSize)] = '1';
                        m[_fix(i+y, mSize)][_fix(j+x, mSize)] = '1';
                        m[_fix(i-x, mSize)][_fix(j+x, mSize)] = '1';
                        m[_fix(i+x, mSize)][_fix(j-x, mSize)] = '1';
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
    private function _makeMasks(template as CodeData) as Array<Array> {
        var nmasks = QRCodeTables.maskPatterns.size();
        var masks = new [nmasks];
        for (var n = 0; n < nmasks; n += 1) {
            var curMask as CodeData = [];
            for (var r = 0; r < template.size(); r += 1) {
                curMask.add(template[r].slice(0, null));
            }
            masks[n] = curMask;
            // Add the type pattern bits to the code
            _addTypePattern(curMask, QRCodeTables.typeBits[QRCodeTables.error[mError]][n].toCharArray());
            // Get the mask pattern
            var pattern = QRCodeTables.maskPatterns[n];
            // This will read the 1's and 0's one at a time
            var bits = mData.toCharArray();
            var b = 0;

            // These will help us do the up, down, up, down pattern
            var rowStart = [curMask.size() - 1, 0];
            var rowStop = [-1, curMask.size()];
            var direction = [-1, 1];
            var mv = 0;

            // The data pattern is added using pairs of columns
            for (var column = curMask.size() - 1; column > 0; column -= 2) {
                // The vertical timing pattern is an exception to the rules, move the column counter over by one
                if (column <= 6) {
                    column -= 1;
                }
                // This will let us fill in the pattern right-left, right-left, etc.
                var columnPair = [column, column - 1];
                var cp = 0;
                // Go through each row in the pattern moving up, then down
                if (mv >= direction.size()) {
                    mv = 0;
                }
                var rStart = rowStart[mv];
                var rStop = rowStop[mv];
                var dir = direction[mv];
                mv += 1;

                for (var row = rStart; (dir > 0 ? row < rStop : row > rStop); row += dir) {
                    // Fill in the right then left column
                    for (var i = 0; i < 2; i += 1) {
                        if (cp >= columnPair.size()) {
                            cp = 0;
                        }
                        var col = columnPair[cp];
                        cp += 1;
                        // Go to the next column if we encounter a preexisting pattern (usually an alignment pattern)
                        if (curMask[row][col] != ' ') {
                            continue;
                        }
                        // Some versions don't have enough bits. You then fill in the rest of the pattern with 0's.
                        // These are called "remainder bits."
                        var bit = b < bits.size() ? bits[b] : 0;
                        b += 1;

                        // If the pattern is True then flip the bit
                        if (pattern.invoke(row, col)) {
                            curMask[row][col] = (bit.toString().toNumber() ^ 1).toString().toCharArray()[0];
                        } else {
                            curMask[row][col] = bit;
                        }
                    }
                }
            }
        }
        return masks;
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
    private function _chooseBestMask() as Number {
        var scores = [];
        for (var i = 0; i < mMasks.size(); i += 1) {
            scores.add([0, 0, 0, 0]);
        }
        // Score penalty rule number 1
        // Look for five consecutive squares with the same color.
        // Each one found gets a penalty of 3 + 1 for every
        // same color square after the first five in the row.
        for (var n = 0; n < mMasks.size(); n += 1) {
            var mask = mMasks[n];
            var current = mask[0][0];
            var counter = 0;
            var total = 0;

            // Examine the mask row wise
            for (var row = 0; row < mMasks.size(); row += 1) {
                counter = 0;
                for (var col = 0; col < mMasks.size(); col += 1) {
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
            for (var col = 0; col < mMasks.size(); col += 1) {
                counter = 0;
                for (var row = 0; row < mMasks.size(); row += 1) {
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
        }
        // Score penalty rule 2
        // This rule will add 3 to the score for each 2x2 block of the same colored pixels there are.
        for (var n = 0; n < mMasks.size(); n += 1) {
            var mask = mMasks[n];
            count = 0;
            // Don't examine the 0th and Nth row/column
            for (var i = 0; i < mMasks.size()-1; i += 1) {
                for (var j = 0; j < mMasks.size()-1; j += 1) {
                    if (mask[i][j] == mask[i+1][j] and mask[i][j] == mask[i][j+1] and mask[i][j] == mask[i+1][j+1]) {
                        count += 1;
                    }
                }
            }
            scores[n][1] = count * 3;
        }
        // Score penalty rule 3
        // This rule looks for 1011101 within the mask prefixed and/or suffixed by four zeros.
        var patterns = [['0','0','0','0','1','0','1','1','1','0','1'],
                    ['1','0','1','1','1','0','1','0','0','0','0']];
                    //[0,0,0,0,1,0,1,1,1,0,1,0,0,0,0]];

        for (var n = 0; n < mMasks.size(); n += 1) {
            var mask = mMasks[n];
            var nmatches = 0;

            for (var i = 0; i < mMasks.size(); i += 1) {
                for (var j = 0; j < mMasks.size(); j += 1) {
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
            }
            scores[n][2] = nmatches * 40;
        }

        // Score the last rule, penalty rule 4. This rule measures how close the pattern is to being 50% black.
        // The further it deviates from this this ideal the higher the penalty.
        for (var n = 0; n < mMasks.size(); n += 1) {
            var mask = mMasks[n];
            var nblack = 0;

            for (var i = 0; i < mask.size(); i += 1) {
                var row = mask[i];
                nblack += _sum(row);
            }
            var totalPixels = Math.pow(mask.size(), 2);
            var ratio = nblack / totalPixels;
            var percent = (ratio * 100) - 50;
            if (percent < 0) {
                percent *= -1;
            }
            scores[n][3] = ((percent / 5).toNumber() * 10);
        }

        // Calculate the total for each score
        var totals = _mult([0], scores.size());
        for (var i = 0; i < scores.size(); i += 1) {
            for (var j = 0; j < scores[i].size(); j += 1) {
                totals[i] += scores[i][j];
            }
        }
        // The lowest total wins
        var minIdx = 0;
        for (var i = 0; i < totals.size(); i += 1) {
            if (totals[i] < totals[minIdx]) {
                minIdx = i;
            }
        }
        return minIdx;
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
            binValue += ((value % 2).toNumber() * Math.pow(10, exp)).toNumber();
            value = (value / 2).toNumber();
            exp += 1;
        }
        return binValue.toNumber().format(Lang.format("%0$1$d", [length]));
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
