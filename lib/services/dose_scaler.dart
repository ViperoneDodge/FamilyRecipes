/// Ricalcola le dosi quando si cambia il numero di persone: "200 g" per 4 → "300 g" per 6.
/// Si scala solo la quantità iniziale (anche "1,5", "1.000", "1/2", "½", "1 1/2", "1½", "2-3", "2–3");
/// il resto ("g", "cucchiai", "q.b.", note tra parentesi) resta com'è.
/// Lingue che scrivono i decimali con il punto (0.8); le altre usano la virgola (0,8).
const Set<String> decimalPointLanguages = {'en', 'ja', 'zh', 'ko', 'th', 'hi', 'ga', 'mt'};

class DoseScaler {
  // Un numero: migliaia all'italiana ("1.000", "12.500"), decimali ("1,5", "0.25"), frazioni ("1/2"),
  // frazioni come carattere ("½"), numeri misti ("1 1/2", "1½", "1 ½").
  static const String _n = r'(?:\d+\s+\d+\s*/\s*\d+|\d+\s*[½¼¾⅓⅔]|\d{1,3}(?:\.\d{3})+(?![\d,.])|'
      r'\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?|[½¼¾⅓⅔])';
  static final RegExp _lead = RegExp('^\\s*($_n)(?:\\s*([-–—])\\s*($_n))?');

  static const Map<String, double> _glyphs = {'½': .5, '¼': .25, '¾': .75, '⅓': 1 / 3, '⅔': 2 / 3};

  static double? _num(String s) {
    s = s.trim();
    // Numero misto: intero + frazione.
    final mixed = RegExp(r'^(\d+)\s*(?:(\d+\s*/\s*\d+)|([½¼¾⅓⅔]))$').firstMatch(s);
    if (mixed != null && (mixed[2] != null || mixed[3] != null) && (mixed[2] == null || s.contains(' '))) {
      final whole = double.parse(mixed[1]!);
      final frac = mixed[2] != null ? _num(mixed[2]!) : _glyphs[mixed[3]!];
      return frac == null ? null : whole + frac;
    }
    s = s.replaceAll(' ', '');
    if (_glyphs.containsKey(s)) return _glyphs[s];
    if (s.contains('/')) {
      final p = s.split('/');
      final a = double.tryParse(p[0].replaceAll(',', '.'));
      final b = double.tryParse(p[1]);
      return a == null || b == null || b == 0 ? null : a / b;
    }
    // "1.000", "12.500": migliaia.
    if (RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(s)) return double.tryParse(s.replaceAll('.', ''));
    return double.tryParse(s.replaceAll(',', '.'));
  }

  static String format(double v, {bool comma = true}) {
    if (v >= 10) return v.round().toString();
    var r = (v * 10).round() / 10;
    var digits = 1;
    // Dosi piccole (zafferano, lievito): non diventano "0".
    while (r == 0 && v > 0 && digits < 3) {
      digits++;
      final p = digits == 2 ? 100 : 1000;
      r = (v * p).round() / p;
    }
    if (r == r.roundToDouble()) return r.round().toString();
    var s = r.toStringAsFixed(digits);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '');
    return comma ? s.replaceAll('.', ',') : s;
  }

  static String scale(String amount, double factor, {bool comma = true}) {
    if (factor == 1) return amount;
    final m = _lead.firstMatch(amount);
    if (m == null) return amount;
    final a = _num(m[1]!);
    if (a == null) return amount;
    var out = format(a * factor, comma: comma);
    if (m[3] != null) {
      final b = _num(m[3]!);
      if (b != null) out = '$out${m[2]}${format(b * factor, comma: comma)}';
    }
    return out + amount.substring(m.end);
  }
}
