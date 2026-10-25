import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/services/sensor_service.dart';
import 'package:noir_final_project/widgets/add_stock_sheet.dart';

void main() {
  final t0 = DateTime(2026, 10, 25, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('TwistDetector', () {
    test('kecepatan rendah tidak dihitung', () {
      final d = TwistDetector();
      expect(d.onSample(0.5, at(0)), 0);
      expect(d.onSample(1.5, at(20)), 0);
      expect(d.onSample(-1.9, at(40)), 0);
    });

    test('searah jarum jam (negatif) = +1, berlawanan (positif) = -1', () {
      expect(TwistDetector().onSample(-3, at(0)), 1);
      expect(TwistDetector().onSample(3, at(0)), -1);
    });

    test('tidak mengulang selama putaran masih cepat', () {
      final d = TwistDetector();
      expect(d.onSample(-3, at(0)), 1);
      expect(d.onSample(-3, at(20)), 0);
      expect(d.onSample(-3, at(700)), 0); // belum pernah turun ke diam
    });

    test('siap lagi setelah berhenti dan lewat jeda', () {
      final d = TwistDetector();
      expect(d.onSample(-3, at(0)), 1);
      expect(d.onSample(0.2, at(100)), 0);
      expect(d.onSample(-3, at(600)), 1);
    });

    test('gerakan kembali yang cepat dalam jeda diabaikan', () {
      final d = TwistDetector();
      expect(d.onSample(-3, at(0)), 1);
      expect(d.onSample(0.2, at(100)), 0);
      expect(d.onSample(3, at(200)), 0);
    });

    test('putaran baru di luar jeda tetap terhitung', () {
      final d = TwistDetector();
      expect(d.onSample(-3, at(0)), 1);
      expect(d.onSample(0.2, at(100)), 0);
      expect(d.onSample(3, at(449)), 0);
      expect(d.onSample(0.2, at(460)), 0);
      expect(d.onSample(3, at(500)), -1);
    });

    test('reset mengembalikan keadaan awal', () {
      final d = TwistDetector();
      expect(d.onSample(-3, at(0)), 1);
      d.reset();
      expect(d.onSample(-3, at(10)), 1);
    });
  });

  group('StockInRules', () {
    test('jumlah dibatasi 1..1000', () {
      expect(StockInRules.clampQty(-5), 1);
      expect(StockInRules.clampQty(0), 1);
      expect(StockInRules.clampQty(7), 7);
      expect(StockInRules.clampQty(1000), 1000);
      expect(StockInRules.clampQty(5000), 1000);
    });
  });
}
