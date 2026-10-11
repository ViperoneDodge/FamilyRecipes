/// Ricalcola le dosi quando si cambia il numero di persone: "200 g" per 4 → "300 g" per 6.
/// Si scala solo il numero iniziale (anche "1,5", "1/2", "½", "2-3"); il resto ("g", "cucchiai",
/// "q.b.", note tra parentesi) resta com'è.
class DoseScaler {
  static final RegExp _lead =
      RegExp(r'^\s*(\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?|[½¼¾⅓⅔])(?:\s*-\s*(\d+(?:[.,]\d+)?))?');

  static const Map<String, double> _glyphs = {'½': .5, '¼': .25, '¾': .75, '⅓': 1 / 3, '⅔': 2 / 3};

  static double? _num(String s) {
    s = s.replaceAll(' ', '');
    if (_glyphs.containsKey(s)) return _glyphs[s];
    if (s.contains('/')) {
      final p = s.split('/');
      final a = double.tryParse(p[0].replaceAll(',', '.'));
      final b = double.tryParse(p[1]);
      return a == null || b == null || b == 0 ? null : a / b;
    }
    return double.tryParse(s.replaceAll(',', '.'));
  }

  static String format(double v, {bool comma = true}) {
    if (v >= 10) return v.round().toString();
    final r = (v * 10).round() / 10;
    if (r == r.roundToDouble()) return r.round().toString();
    final s = r.toStringAsFixed(1);
    return comma ? s.replaceAll('.', ',') : s;
  }

  static String scale(String amount, double factor, {bool comma = true}) {
    if (factor == 1) return amount;
    final m = _lead.firstMatch(amount);
    if (m == null) return amount;
    final a = _num(m[1]!);
    if (a == null) return amount;
    var out = format(a * factor, comma: comma);
    if (m[2] != null) {
      final b = _num(m[2]!);
      if (b != null) out = '$out-${format(b * factor, comma: comma)}';
    }
    return out + amount.substring(m.end);
  }
}
