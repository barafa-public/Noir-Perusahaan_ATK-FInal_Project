import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/models/product_model.dart';
import 'package:noir_final_project/services/forecast_service.dart';
import 'package:noir_final_project/services/time_service.dart';

final DateTime now = DateTime.utc(2026, 10, 28, 5); // Rabu 28 Okt, 12.00 WIB
const AppZone zone = AppZone.wib;
final int todayKey = ForecastService.dayKey(now, zone);

ProductModel prod(
  String id, {
  int stock = 20,
  int minStock = 5,
  bool active = true,
}) =>
    ProductModel(
      id: id,
      sku: 'SKU-$id',
      name: 'Produk $id',
      category: 'ATK',
      price: 5000,
      stock: stock,
      minStock: minStock,
      isActive: active,
      updatedAt: '2026-10-01T00:00:00.000Z',
    );

DateTime noonOf(int key) => TimeService.toUtc(
      DateTime.utc(1970, 1, 1).add(Duration(days: key, hours: 12)),
      zone,
    );

/// Satu catatan penjualan per hari untuk [days] hari terakhir.
List<SaleRecord> daily(String id, int days, int Function(int key) qty) => [
      for (var d = days; d >= 1; d--)
        if (qty(todayKey - d) > 0)
          SaleRecord(id, noonOf(todayKey - d), qty(todayKey - d)),
    ];

ForecastReport build(
  List<ProductModel> products,
  List<SaleRecord> sales, {
  int historyDays = 28,
  ForecastConfig config = const ForecastConfig(),
}) =>
    ForecastService.buildReport(
      products: products,
      sales: sales,
      firstSaleAtUtc: historyDays == 0 ? null : noonOf(todayKey - historyDays),
      nowUtc: now,
      zone: zone,
      config: config,
    );

void main() {
  group('hari', () {
    test('dayOfWeek: 28 Okt 2026 adalah Rabu (2)', () {
      expect(ForecastService.dayOfWeek(todayKey), 2);
    });

    test('dayKey mengikuti zona: 18.30 UTC = 01.30 WIB hari berikutnya', () {
      expect(
        ForecastService.dayKey(DateTime.utc(2026, 10, 27, 18, 30), zone),
        todayKey,
      );
      expect(
        ForecastService.dayKey(DateTime.utc(2026, 10, 27, 17, 30), zone),
        todayKey - 1,
      );
    });
  });

  group('permintaan konstan 3 per hari', () {
    final sales = daily('A', 28, (_) => 3);

    test('prediksi dan sisa hari', () {
      final f = build([prod('A', stock: 24)], sales).items.single;
      expect(f.predictedDaily, closeTo(3, 0.01));
      expect(f.daysLeft, closeTo(8, 0.05));
      expect(f.wape, closeTo(0, 0.01));
      expect(f.confidence, Confidence.high);
      expect(f.basedOnForecast, isTrue);
    });

    test('stok menipis: segera dan saran restock 27', () {
      final f = build([prod('A', stock: 24)], sales).items.single;
      expect(f.urgency, Urgency.soon);
      expect(f.restockQty, 27); // 3 × (3 + 14) = 51 − 24
    });

    test('stok banyak: aman, tanpa saran', () {
      final f = build([prod('A', stock: 60)], sales).items.single;
      expect(f.urgency, Urgency.ok);
      expect(f.restockQty, 0);
      expect(f.daysLeft, closeTo(20, 0.05));
    });

    test('stok habis: mendesak', () {
      final f = build([prod('A', stock: 0)], sales).items.single;
      expect(f.urgency, Urgency.critical);
      expect(f.daysLeft, 0);
      expect(f.restockQty, greaterThan(0));
    });

    test('cakupan lebih lama menaikkan saran restock', () {
      final f = build(
        [prod('A', stock: 24)],
        sales,
        config: const ForecastConfig(coverDays: 21),
      ).items.single;
      expect(f.restockQty, 48); // 3 × (3 + 21) = 72 − 24
    });
  });

  test('tanpa permintaan: tidak habis, aman, perputaran lambat', () {
    final f = build([prod('A', stock: 20)], const []).items.single;
    expect(f.predictedDaily, 0);
    expect(f.daysLeft, isNull);
    expect(f.urgency, Urgency.ok);
    expect(f.restockQty, 0);
    expect(f.slow, isTrue);
  });

  test('tren naik: prediksi di atas rata-rata riwayat', () {
    final sales = daily('A', 28, (key) => 1 + (key - (todayKey - 28)) ~/ 2);
    final f = build([prod('A', stock: 50)], sales).items.single;
    expect(f.predictedDaily, greaterThan(f.recentAvg));
    expect(f.trendPct, isNotNull);
    expect(f.trendPct!, greaterThan(0));
  });

  test('pola mingguan: Sabtu diprediksi jauh lebih ramai dari Senin', () {
    final sales = daily(
      'A',
      28,
      (key) => ForecastService.dayOfWeek(key) == 5 ? 10 : 2,
    );
    final f = build([prod('A', stock: 100)], sales).items.single;
    final kSat = List.generate(7, (k) => k)
        .firstWhere((k) => ForecastService.dayOfWeek(todayKey + k) == 5);
    final kMon = List.generate(7, (k) => k)
        .firstWhere((k) => ForecastService.dayOfWeek(todayKey + k) == 0);
    expect(f.next7[kSat], greaterThan(f.next7[kMon] * 2));
  });

  group('data belum cukup', () {
    final sales = daily('A', 3, (_) => 2);

    test('keyakinan tidak cukup dan memakai stok minimum', () {
      final f =
          build([prod('A', stock: 2)], sales, historyDays: 3).items.single;
      expect(f.confidence, Confidence.insufficient);
      expect(f.basedOnForecast, isFalse);
      expect(f.urgency, Urgency.soon);
      expect(f.restockQty, 8); // 5 × 2 − 2
    });

    test('stok kosong: mendesak', () {
      final f =
          build([prod('A', stock: 0)], sales, historyDays: 3).items.single;
      expect(f.urgency, Urgency.critical);
      expect(f.restockQty, 10);
    });

    test('stok cukup: aman', () {
      final f =
          build([prod('A', stock: 50)], sales, historyDays: 3).items.single;
      expect(f.urgency, Urgency.ok);
      expect(f.restockQty, 0);
    });

    test('belum ada penjualan sama sekali tidak membuat galat', () {
      final r = build([prod('A'), prod('B')], const [], historyDays: 0);
      expect(r.items.length, 2);
      expect(r.historyDays, 0);
      expect(
        r.items.every((f) => f.confidence == Confidence.insufficient),
        isTrue,
      );
    });
  });

  test('penjualan hari ini tidak ikut riwayat', () {
    final sales = [
      ...daily('A', 28, (_) => 3),
      SaleRecord('A', now, 99), // hari ini, belum lengkap
    ];
    final f = build([prod('A')], sales).items.single;
    expect(f.history.length, 28);
    expect(f.history.reduce((a, b) => a + b), 84);
  });

  test('urutan: yang paling mendesak di atas, produk nonaktif dilewati', () {
    final r = build(
      [
        prod('A', stock: 100),
        prod('B', stock: 5),
        prod('X', stock: 0, active: false),
      ],
      [...daily('A', 28, (_) => 3), ...daily('B', 28, (_) => 3)],
    );
    expect(r.items.length, 2);
    expect(r.items.first.product.id, 'B');
    expect(r.items.first.urgency, Urgency.critical);
    expect(r.countOf(Urgency.ok), 1);
  });

  group('data contoh', () {
    final products = [for (var i = 0; i < 6; i++) prod('P$i', stock: 12 + i)];

    test('deterministik dan semua jumlah positif', () {
      final a = DemoSales.generate(products, now, zone);
      final b = DemoSales.generate(products, now, zone);
      expect(a.sales.length, b.sales.length);
      expect(a.sales.isNotEmpty, isTrue);
      expect(a.sales.every((s) => s.qty > 0), isTrue);
      expect(a.sales.first.qty, b.sales.first.qty);
    });

    test('hasil prediksi terbatas dan masuk akal', () {
      final d = DemoSales.generate(products, now, zone);
      final r = ForecastService.buildReport(
        products: products,
        sales: d.sales,
        firstSaleAtUtc: d.firstSaleAtUtc,
        nowUtc: now,
        zone: zone,
        demo: true,
      );
      expect(r.items.length, 6);
      expect(r.historyDays, 28);
      for (final f in r.items) {
        expect(f.predictedDaily.isFinite, isTrue);
        expect(f.predictedDaily, greaterThanOrEqualTo(0));
        expect(f.restockQty, greaterThanOrEqualTo(0));
        expect(f.targetStock.isFinite, isTrue);
        expect(f.next7.length, 7);
        expect(f.next7.every((v) => v.isFinite && v >= 0), isTrue);
      }
    });
  });
}
