/// Splits streamed LLM text into sentences so we can start speaking the first
/// sentence while the rest of the answer is still arriving.
class SentenceSplitter {
  final _buf = StringBuffer();

  static final _boundary = RegExp(
    r'[.!?\u2026\u3002\uFF01\uFF1F\u0964]+["\x27)\]]*\s+|\n+',
  );

  /// Adds a streamed chunk and returns any sentences that are now complete.
  List<String> add(String chunk) {
    _buf.write(chunk);
    final out = <String>[];
    var text = _buf.toString();
    while (true) {
      final m = _boundary.firstMatch(text);
      if (m == null) break;
      final sentence = text.substring(0, m.end).trim();
      text = text.substring(m.end);
      if (sentence.isNotEmpty) out.add(sentence);
    }
    // Very long run-on text: cut at the last comma or space to keep latency low.
    if (text.length > 220) {
      var cut = text.lastIndexOf(', ', 200);
      if (cut < 60) cut = text.lastIndexOf(' ', 200);
      if (cut > 0) {
        out.add(text.substring(0, cut + 1).trim());
        text = text.substring(cut + 1);
      }
    }
    _buf
      ..clear()
      ..write(text);
    return out;
  }

  /// Returns whatever is left once the stream has ended.
  String flush() {
    final rest = _buf.toString().trim();
    _buf.clear();
    return rest;
  }
}

/// Removes markdown and symbols that sound bad when read aloud.
String cleanForSpeech(String text) {
  return text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[*_`#>|~]+'), '')
      .replaceAll(RegExp(r'^\s*[-\u2022]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
