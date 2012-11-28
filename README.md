Huffman compression/decompression
=================================

Example:

`d
auto weights = [22, 12, 29, 6, 21, 9];
auto alphabet = "abcdef"d;

// 6, 9 -> 15    | 29 22 21 15 12
// 12, 15 -> 27  | 29 27 22 21
// 21, 22 -> 43  | 43 29 27
// 27, 29 -> 56  | 56 43
//
// Huffman tree:
//
//                   * [a, b, c, d, e, f]
//                  / \
//                 /   \
//                /     \
//  [b, c, d, f] 1       0  [a, e]
//              / \      | \
//   [b, d, f] 0   1     1  0 [e]
//            /|  [c]   [a]
//           / |
//   [d, f] 1  0 [b]
//         / \
//    [f] 1   0 [d]
//

auto encoding = huffmanEncoding(weights, alphabet);

assert(equal(
        encoding.decode(
            bits(0b00_100_100_01_01_00_01_01_1011_11).take(24).retro()), 
        "ebbaaeaafc"));
`
