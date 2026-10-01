import 'dart:convert';

import 'package:flutter/services.dart';

/// CLIP's text tokenizer (byte-level BPE), the same as OpenAI's.
/// Turns text like "a photo of a cat" into the token IDs the text model expects.
class ClipTokenizer {
  static const int startToken = 49406; // <|startoftext|>
  static const int endToken = 49407; // <|endoftext|>
  static const int contextLength = 77; // CLIP always takes exactly 77 tokens

  final Map<String, int> _vocab; // word piece -> ID
  final Map<String, int> _mergeRanks; // "a b" -> priority (lower merges first)
  final Map<int, String> _byteToChar = _bytesToUnicode();
  final Map<String, String> _cache = {};

  /// Splits text into words, numbers and punctuation (CLIP's exact rule).
  static final RegExp _pattern = RegExp(
    r"""<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+""",
    caseSensitive: false,
    unicode: true,
  );

  ClipTokenizer._(this._vocab, this._mergeRanks);

  /// Loads the tokenizer from the app's assets.
  static Future<ClipTokenizer> load() async {
    final vocabJson = await rootBundle.loadString('assets/clip_vocab.json');
    final mergesTxt = await rootBundle.loadString('assets/clip_merges.txt');
    return ClipTokenizer.fromStrings(vocabJson, mergesTxt);
  }

  factory ClipTokenizer.fromStrings(String vocabJson, String mergesTxt) {
    final vocab = (jsonDecode(vocabJson) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as int),
    );
    final ranks = <String, int>{};
    final lines = const LineSplitter().convert(mergesTxt);
    for (final line in lines.skip(1)) {
      // first line is a "#version" header
      if (line.trim().isEmpty) continue;
      ranks[line] = ranks.length;
    }
    return ClipTokenizer._(vocab, ranks);
  }

  /// Returns exactly 77 IDs: [start, ...tokens, end, 0, 0, ...]
  List<int> encode(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final ids = <int>[startToken];
    for (final match in _pattern.allMatches(cleaned)) {
      final token = utf8
          .encode(match.group(0)!)
          .map((b) => _byteToChar[b]!)
          .join();
      for (final piece in _bpe(token).split(' ')) {
        final id = _vocab[piece];
        if (id != null) ids.add(id);
      }
    }
    if (ids.length > contextLength - 1) ids.length = contextLength - 1;
    ids.add(endToken);
    while (ids.length < contextLength) {
      ids.add(0);
    }
    return ids;
  }

  /// Byte-pair encoding: starts with single characters and repeatedly glues
  /// together the highest-priority pair until no known pair is left.
  String _bpe(String token) {
    final cached = _cache[token];
    if (cached != null) return cached;
    final chars = token.split('');
    var word = [...chars.sublist(0, chars.length - 1), '${chars.last}</w>'];
    while (word.length > 1) {
      int? bestRank;
      var bestIndex = -1;
      for (var i = 0; i < word.length - 1; i++) {
        final rank = _mergeRanks['${word[i]} ${word[i + 1]}'];
        if (rank != null && (bestRank == null || rank < bestRank)) {
          bestRank = rank;
          bestIndex = i;
        }
      }
      if (bestRank == null) break;
      final first = word[bestIndex];
      final second = word[bestIndex + 1];
      final merged = <String>[];
      var i = 0;
      while (i < word.length) {
        if (i < word.length - 1 && word[i] == first && word[i + 1] == second) {
          merged.add(first + second);
          i += 2;
        } else {
          merged.add(word[i]);
          i += 1;
        }
      }
      word = merged;
    }
    final result = word.join(' ');
    _cache[token] = result;
    return result;
  }

  /// Maps every byte (0-255) to a printable character, as CLIP does,
  /// so any text (emoji, accents) can be tokenized.
  static Map<int, String> _bytesToUnicode() {
    final bytes = <int>[
      for (var b = 33; b <= 126; b++) b,
      for (var b = 161; b <= 172; b++) b,
      for (var b = 174; b <= 255; b++) b,
    ];
    final chars = [...bytes];
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bytes.contains(b)) {
        bytes.add(b);
        chars.add(256 + n);
        n++;
      }
    }
    return {
      for (var i = 0; i < bytes.length; i++)
        bytes[i]: String.fromCharCode(chars[i]),
    };
  }
}
