module huffman;

import std.range;
import std.container;
import std.traits;
import std.typecons;
import std.exception;
import std.array;

private {
    struct HuffmanNode(T) {
        union {
            struct {
                HuffmanNode* left;
                HuffmanNode* right;
            }
            size_t index;
        }

        bool isLeaf;
        T weight;
    }
}

/// Single bit
enum Bit : byte {
    Zero,
    One
}

struct IntegralBitRange(T) 
{
    private T _n;
    private size_t _len;

    this(T number, size_t length = T.sizeof * 8) {
        _n = number;
        _len = length;
    }

    bool empty() @property const { return _len == 0; }

    Bit front() @property const { return this[0]; }

    Bit back() @property const { return this[_len - 1]; }

    void popFront() { --_len; _n >>= 1; }

    void popBack() { --_len; }

    Bit opIndex(size_t index) const { 
        return (_n & (1 << index)) == 0 ? Bit.Zero : Bit.One; 
    }

    size_t length() @property const { return _len; }

    IntegralBitRange!T save() @property const { return IntegralBitRange(_n, _len); }

    IntegralBitRange!T opSlice(size_t i, size_t j) const {
        return IntegralBitRange(_n >> i, j - i);
    }
}

static assert(isRandomAccessRange!(IntegralBitRange!int));

/// Bits of a number, starting from lowest one.
auto bits(T)(T number)
    if (isIntegral!T)
{
    return IntegralBitRange!T(number);
}

unittest {
    import std.algorithm;
    import std.range;
    assert(equal(bits(0b0001010011).take(10), [1, 1, 0, 0, 1, 0, 1, 0, 0, 0]));
}

/// Stores information about Huffman encoding
struct HuffmanEncoding(W, A) 
    if (isRandomAccessRange!W && isRandomAccessRange!A &&
        __traits(compiles, { W weights;
                             bool b = weights.front < weights.front + weights.front; 
                             ulong[ElementType!A] table; }))
{
    private {
        alias HuffmanNode!(ElementType!W) Node;
        Node* _root;
        A _alphabet;
        ulong[ElementType!A] _codes; // code = (length << 58) + (...c_n ... c0)
    }

    alias ElementType!A Character;

    /// Create new encoding from alphabet and letter frequencies.
    /// $(D weights) and $(D alphabet) must both be random-access ranges
    /// and have the same length.
    this(W weights, A alphabet) 
    {
        enforce(weights.length == alphabet.length, 
                "Weights and alphabet must have the same length");

        _alphabet = alphabet;

        alias Array!(Node*) WeightStore;

        WeightStore heap_store;
        heap_store.reserve(weights.length);

        static bool weightHeapPredicate(Node* f1, Node* f2) {
            return f1.weight > f2.weight;
        }

        auto queue = BinaryHeap!(WeightStore, weightHeapPredicate)(heap_store);
        foreach (size_t i, w; weights) {
            Node* node = new Node;
            node.isLeaf = true;
            node.weight = w;
            node.index = i;
            queue.insert(node);
        }

        while (queue.length >= 2) {
            auto w1 = queue.front;
            queue.removeFront();

            auto w2 = queue.front;
            queue.removeFront();

            Node* parent = new Node;
            parent.isLeaf = false;
            parent.weight = w1.weight + w2.weight;
            parent.left = w1;
            parent.right = w2;

            queue.insert(parent);
        }

        _root = queue.front;

        createCodeTable();
    }

    private void createCodeTable() {
        codeTableVisit(_root, 0, 0);
    }

    private void codeTableVisit(Node* node, int depth, ulong code) {
        enforce(depth < 58, "Huffman tree is too deep!");
        if (node.isLeaf) {
            _codes[_alphabet[node.index]] = (cast(ulong)depth << 58) + code;
        } else {
            codeTableVisit(node.left, depth + 1, code);
            codeTableVisit(node.right, depth + 1, code + (1UL << depth));
        }
    }

    /// Get range of bits encoding a character from the alphabet.
    IntegralBitRange!ulong encode(S)(S character) const
        if (is(S : Character))
    {
        ulong code = _codes[character];
        ubyte length = cast(ubyte)(code >> 58);
        return IntegralBitRange!ulong(code, length);
    }

    static struct BitRange(S) 
        if (isInputRange!S && is(ElementType!S : Character))
    {
        private {
            S _seq;
            const(HuffmanEncoding*) _enc;
            IntegralBitRange!ulong _cur_range;
            bool _empty;
        }

        this(S sequence, const(HuffmanEncoding*) enc) {
            _seq = sequence;
            _enc = enc;

            if (_seq.empty) {
                _empty = true;
            } else {
                _cur_range = _enc.encode(_seq.front);
                _seq.popFront();
            }
        }

        Bit front() @property const {
            return _cur_range.front;
        }

        bool empty() @property const {
            return _empty;
        }

        void popFront() {
            _cur_range.popFront();
            while (_cur_range.empty) {
                if (_seq.empty) {
                    _empty = true;
                    break;
                } else {
                    _cur_range = _enc.encode(_seq.front);
                    _seq.popFront();
                }
            } 
        }
    }

    BitRange!S encode(S)(S sequence) const
        if (isInputRange!S && is(ElementType!S : Character))
    {
        return BitRange!S(sequence, &this);
    }

    static struct CharacterRange(S) {
        
        private {
            S _bits;
            Node* _root;
            Node* _current_node;
            A _alphabet;
            bool _empty;
        }

        this(S bits, Node* root, A alphabet) {
            _root = root;
            _bits = bits;
            _alphabet = alphabet;
            setupFront();
        }

        void popFront() {
            setupFront();
        }

        Character front() @property const {
            return _alphabet[_current_node.index];
        }

        bool empty() @property const {
            return _empty;
        }

        private void setupFront() {
            _current_node = _root;
            while (!_bits.empty) {
                auto _bit = _bits.front;
                _bits.popFront();

                final switch(_bit) {
                    case Bit.Zero:
                        _current_node = _current_node.left;
                        break;
                    case Bit.One:
                        _current_node = _current_node.right;
                        break;
                }

                if (_current_node.isLeaf)
                    break;
            }

            if (!_current_node.isLeaf) {
                _empty = true;
            }
        }
    }

    /// Convert stream of bits into a range of characters from alphabet
    CharacterRange!S decode(S)(S bits)
        if (isInputRange!S && is(ElementType!S == Bit)) 
    {
        return CharacterRange!S(bits, _root, _alphabet);
    }
}

///
HuffmanEncoding!(W, A) huffmanEncoding(W, A)(W weights, A alphabet) {
    return HuffmanEncoding!(W, A)(weights, alphabet);
}

unittest {
    import std.stdio;
    import std.algorithm;
    import std.range;

    auto weights = [22, 12, 29, 6, 21, 9];
    auto alphabet = "abcdef"d;

    auto encoding = huffmanEncoding(weights, alphabet);

    assert(equal(encoding.encode('a'), [0, 1]));
    assert(equal(encoding.encode('b'), [1, 0, 0]));
    assert(equal(encoding.encode('c'), [1, 1]));
    assert(equal(encoding.encode('d'), [1, 0, 1, 0]));
    assert(equal(encoding.encode('e'), [0, 0]));
    assert(equal(encoding.encode('f'), [1, 0, 1, 1]));

    auto data = bits(0b00_100_100_01_01_00_01_01_1011_11).takeExactly(24).retro();
    auto str = "ebbaaeaafc";
    assert(equal(str, encoding.decode(encoding.encode(str))));
    assert(equal(data, encoding.encode(encoding.decode(data))));
}
