import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/services/sensor_service.dart';

void main() {
  final t0 = DateTime(2026, 10, 22, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  const calm = 9.8; // diam: sekitar 1 g
  const hard = 30.0; // sekitar 3 g

  test('magnitude vektor', () {
    final r = SensorReading(3, 4, 12, t0);
    expect(r.magnitude, closeTo(13, 1e-9));
  });

  test('kondisi diam tidak dianggap goyangan', () {
    final d = ShakeDetector();
    for (var i = 0; i < 50; i++) {
      expect(d.onSample(calm, at(i * 20)), isFalse);
    }
  });

  test('satu hentakan saja belum goyangan', () {
    final d = ShakeDetector();
    expect(d.onSample(hard, at(0)), isFalse);
  });

  test('dua hentakan dalam 800 ms = goyangan', () {
    final d = ShakeDetector();
    expect(d.onSample(hard, at(0)), isFalse);
    expect(d.onSample(hard, at(300)), isTrue);
  });

  test('hentakan yang sama (< 120 ms) dihitung satu', () {
    final d = ShakeDetector();
    expect(d.onSample(hard, at(0)), isFalse);
    expect(d.onSample(hard, at(40)), isFalse);
    expect(d.onSample(hard, at(80)), isFalse);
  });

  test('dua hentakan terlalu jauh (> 800 ms) bukan goyangan', () {
    final d = ShakeDetector();
    expect(d.onSample(hard, at(0)), isFalse);
    expect(d.onSample(hard, at(1000)), isFalse);
  });

  test('jeda setelah goyangan terdeteksi', () {
    final d = ShakeDetector();
    d.onSample(hard, at(0));
    expect(d.onSample(hard, at(300)), isTrue);
    // Masih dalam jeda 1,5 detik.
    d.onSample(hard, at(600));
    expect(d.onSample(hard, at(900)), isFalse);
    // Setelah jeda.
    d.onSample(hard, at(2000));
    expect(d.onSample(hard, at(2300)), isTrue);
  });
}
