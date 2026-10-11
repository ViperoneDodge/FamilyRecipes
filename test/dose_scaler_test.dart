import 'package:familyrecipes/services/dose_scaler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dosi ricalcolate', () {
    expect(DoseScaler.scale('200 g', 1.5), '300 g');
    expect(DoseScaler.scale('1,5 l', 2), '3 l');
    expect(DoseScaler.scale('1/2 bustina', 2), '1 bustina');
    expect(DoseScaler.scale('½ cucchiaino', 3), '1,5 cucchiaino');
    expect(DoseScaler.scale('2-3 foglie', 2), '4-6 foglie');
    expect(DoseScaler.scale('3', 1 / 3), '1');
    expect(DoseScaler.scale('125 g (provare 110)', 2), '250 g (provare 110)');
    expect(DoseScaler.scale('q.b.', 2), 'q.b.');
    expect(DoseScaler.scale('un pizzico', 2), 'un pizzico');
    expect(DoseScaler.scale('2 uova', 0.5), '1 uova');
    expect(DoseScaler.scale('1 kg', 0.75, comma: false), '0.8 kg');
  });
}
