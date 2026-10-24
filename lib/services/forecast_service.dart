import 'dart:math' as math;

import '../models/product_model.dart';
import '../models/sale_model.dart';
import 'db_helper.dart';
import 'time_service.dart';

// =====================================================================
// Prediksi kebutuhan stok dan rekomendasi restock
// Model: regresi linear (OLS) dengan tren terredam dan faktor hari dalam
// minggu, dilatih per produk dari riwayat penjualan. Seluruhnya berjalan
// di perangkat, tanpa jaringan.
// =====================================================================

class ForecastConfig {
  /// Panjang riwayat yang dipakai (hari lengkap sebelum hari ini).
  final int windowDays;

  /// Lama menunggu barang datang sejak dipesan.
  final int leadTimeDays;

  /// Stok yang dibeli diharapkan cukup untuk sekian hari setelah barang datang.
  final int coverDays;

  /// Faktor stok pengaman (1,28 = tingkat layanan sekitar 90%).
  final double serviceZ;

  /// Peredam tren (0..1). Makin kecil, prediksi makin datar.
  final double damping;

  /// Riwayat toko minimal (hari) agar model mau memprediksi.
  final int minHistoryDays;

  /// Jumlah hari yang disembunyikan untuk menguji model (backtest).
  final int backtestDays;

  const ForecastConfig({
    this.windowDays = 28,
    this.leadTimeDays = 3,
    this.coverDays = 14,
    this.serviceZ = 1.28,
    this.damping = 0.9,
    this.minHistoryDays = 7,
    this.backtestDays = 7,
  });

  int get planningDays => leadTimeDays + coverDays;

  ForecastConfig copyWith({int? leadTimeDays, int? coverDays}) =>
      ForecastConfig(
        windowDays: windowDays,
        leadTimeDays: leadTimeDays ?? this.leadTimeDays,
        coverDays: coverDays ?? this.coverDays,
        serviceZ: serviceZ,
        damping: damping,
        minHistoryDays: minHistoryDays,
        backtestDays: backtestDays,
      );
}

enum Urgency { critical, soon, ok }

enum Confidence { insufficient, low, medium, high }

class SaleRecord {
  final String productId;
  final DateTime soldAtUtc;
  final int qty;

  const SaleRecord(this.productId, this.soldAtUtc, this.qty);
}

class ProductForecast {
  final ProductModel product;

  /// Terjual per hari, dari terlama sampai kemarin.
  final List<double> history;

  /// Prediksi 7 hari, dimulai dari hari ini. Kosong jika data belum cukup.
  final List<double> next7;

  final double recentAvg;
  final double predictedDaily;
  final double weekTotal;

  /// Perubahan 7 hari terakhir dibanding 7 hari sebelumnya (0,2 = naik 20%).
  final double? trendPct;

  /// Perkiraan stok habis dalam sekian hari; null = tidak habis dalam 60 hari.
  final double? daysLeft;

  final double horizonDemand;
  final double safetyStock;
  final double targetStock;
  final int restockQty;
  final Urgency urgency;
  final Confidence confidence;

  /// Galat relatif backtest (0 = sempurna); null jika belum bisa diukur.
  final double? wape;

  /// true = dihitung dari model; false = cadangan berdasarkan stok minimum.
  final bool basedOnForecast;

  /// Hampir tidak ada permintaan sementara stok di atas minimum.
  final bool slow;

  const ProductForecast({
    required this.product,
    required this.history,
    required this.next7,
    required this.recentAvg,
    required this.predictedDaily,
    required this.weekTotal,
    required this.trendPct,
    required this.daysLeft,
    required this.horizonDemand,
    required this.safetyStock,
    required this.targetStock,
    required this.restockQty,
    required this.urgency,
    required this.confidence,
    required this.wape,
    required this.basedOnForecast,
    required this.slow,
  });
}

class ForecastReport {
  final List<ProductForecast> items;

  /// Jumlah hari riwayat toko yang dipakai (maks. windowDays).
  final int historyDays;
  final DateTime generatedAt;
  final AppZone zone;
  final bool demo;
  final ForecastConfig config;

  const ForecastReport({
    required this.items,
    required this.historyDays,
    required this.generatedAt,
    required this.zone,
    required this.demo,
    required this.config,
  });

  int countOf(Urgency u) => items.where((f) => f.urgency == u).length;
}

class _Model {
  final int n;
  final int firstDow;
  final double a;
  final double b;
  final double sigma;
  final double damping;
  final List<double> s; // faktor hari, indeks 0 = Senin

  const _Model({
    required this.n,
    required this.firstDow,
    required this.a,
    required this.b,
    required this.sigma,
    required this.damping,
    required this.s,
  });

  /// Prediksi permintaan pada indeks hari [t] (0 = hari pertama riwayat).
  double forecastAt(int t) {
    final season = s[(firstDow + t) % 7];
    final k = t - (n - 1);
    if (k <= 0) return math.max(0.0, a + b * t) * season;
    final level = a + b * (n - 1);
    var damp = 0.0;
    var p = 1.0;
    for (var i = 1; i <= k; i++) {
      p *= damping;
      damp += p;
    }
    return math.max(0.0, level + b * damp) * season;
  }
}

class ForecastService {
  ForecastService._();
  static final ForecastService instance = ForecastService._();

  static const int _horizon = 60;

  // ------------------------------------------------------------------
  // Hari
  // ------------------------------------------------------------------

  /// Nomor hari (sejak 1970-01-01) pada zona [zone].
  static int dayKey(DateTime utc, AppZone zone) {
    final w = TimeService.toZone(utc, zone);
    return DateTime.utc(w.year, w.month, w.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  /// 0 = Senin ... 6 = Minggu. (1 Jan 1970 adalah hari Kamis.)
  static int dayOfWeek(int key) => (key + 3) % 7;

  // ------------------------------------------------------------------
  // Pemuatan data
  // ------------------------------------------------------------------

  Future<ForecastReport> loadReport({
    ForecastConfig config = const ForecastConfig(),
    bool demo = false,
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final zone = TimeService.instance.displayZone.value;
    final products = (await DbHelper.instance.getProducts())
        .where((p) => p.isActive)
        .toList();

    final List<SaleRecord> sales;
    final DateTime? first;
    if (demo) {
      final d = DemoSales.generate(products, now, zone);
      sales = d.sales;
      first = d.firstSaleAtUtc;
    } else {
      final since = SaleModel.normalizeIso(
        now.subtract(Duration(days: config.windowDays + 2)),
      );
      final rows = await DbHelper.instance.getSaleQuantitiesSince(since);
      final list = <SaleRecord>[];
      for (final r in rows) {
        final t = DateTime.tryParse(r.soldAt)?.toUtc();
        if (t != null) list.add(SaleRecord(r.productId, t, r.qty));
      }
      sales = list;
      final f = await DbHelper.instance.getFirstSaleAt();
      first = f == null ? null : DateTime.tryParse(f)?.toUtc();
    }

    return buildReport(
      products: products,
      sales: sales,
      firstSaleAtUtc: first,
      nowUtc: now,
      zone: zone,
      config: config,
      demo: demo,
    );
  }

  // ------------------------------------------------------------------
  // Inti perhitungan (murni, mudah diuji)
  // ------------------------------------------------------------------

  static ForecastReport buildReport({
    required List<ProductModel> products,
    required List<SaleRecord> sales,
    required DateTime? firstSaleAtUtc,
    required DateTime nowUtc,
    required AppZone zone,
    ForecastConfig config = const ForecastConfig(),
    bool demo = false,
  }) {
    final todayKey = dayKey(nowUtc, zone);
    final firstKey =
        firstSaleAtUtc == null ? null : dayKey(firstSaleAtUtc, zone);
    final startKey = firstKey == null
        ? todayKey
        : math.max(todayKey - config.windowDays, firstKey);
    final n = math.max(0, todayKey - startKey);

    final series = <String, List<double>>{};
    for (final s in sales) {
      final k = dayKey(s.soldAtUtc, zone);
      if (k < startKey || k >= todayKey) continue;
      final list = series.putIfAbsent(
        s.productId,
        () => List<double>.filled(n, 0.0),
      );
      list[k - startKey] += s.qty;
    }

    final firstDow = dayOfWeek(startKey);
    final items = <ProductForecast>[];
    for (final p in products) {
      if (!p.isActive) continue;
      final y = series[p.id] ?? List<double>.filled(n, 0.0);
      items.add(_forecastProduct(p, y, firstDow, config));
    }

    items.sort((a, b) {
      final u = a.urgency.index.compareTo(b.urgency.index);
      if (u != 0) return u;
      final da = a.daysLeft ?? double.infinity;
      final db = b.daysLeft ?? double.infinity;
      final c = da.compareTo(db);
      if (c != 0) return c;
      return a.product.name.toLowerCase().compareTo(
            b.product.name.toLowerCase(),
          );
    });

    return ForecastReport(
      items: items,
      historyDays: n,
      generatedAt: nowUtc,
      zone: zone,
      demo: demo,
      config: config,
    );
  }

  static ProductForecast _forecastProduct(
    ProductModel p,
    List<double> y,
    int firstDow,
    ForecastConfig c,
  ) {
    final n = y.length;
    var total = 0.0;
    for (final v in y) {
      total += v;
    }
    final recentAvg = n == 0 ? 0.0 : total / n;

    // ----- Data belum cukup: cadangan berdasarkan stok minimum -----
    if (n < c.minHistoryDays) {
      final out = p.stock <= 0;
      final low = p.stock <= p.minStock;
      return ProductForecast(
        product: p,
        history: y,
        next7: const [],
        recentAvg: recentAvg,
        predictedDaily: 0,
        weekTotal: 0,
        trendPct: null,
        daysLeft: out ? 0.0 : null,
        horizonDemand: 0,
        safetyStock: 0,
        targetStock: (p.minStock * 2).toDouble(),
        restockQty: low ? math.max(1, p.minStock * 2 - p.stock) : 0,
        urgency: out
            ? Urgency.critical
            : low
                ? Urgency.soon
                : Urgency.ok,
        confidence: Confidence.insufficient,
        wape: null,
        basedOnForecast: false,
        slow: false,
      );
    }

    // ----- Model -----
    final model = _fit(y, firstDow, c.damping);
    final preds = List<double>.generate(
      _horizon,
      (k) => model.forecastAt(n + k),
    );
    final next7 = preds.sublist(0, 7);
    var weekTotal = 0.0;
    for (final v in next7) {
      weekTotal += v;
    }
    final predictedDaily = weekTotal / 7;

    // Tren: 7 hari terakhir dibanding 7 hari sebelumnya.
    double? trend;
    if (n >= 14) {
      var last7 = 0.0;
      var prev7 = 0.0;
      for (var i = n - 7; i < n; i++) {
        last7 += y[i];
      }
      for (var i = n - 14; i < n - 7; i++) {
        prev7 += y[i];
      }
      if (prev7 > 0.0001) trend = last7 / prev7 - 1;
    }

    // Backtest: sembunyikan hari terakhir, prediksi, bandingkan.
    double? wape;
    if (n >= c.backtestDays * 3) {
      final trainN = n - c.backtestDays;
      final m = _fit(y.sublist(0, trainN), firstDow, c.damping);
      var err = 0.0;
      var act = 0.0;
      for (var i = 0; i < c.backtestDays; i++) {
        err += (m.forecastAt(trainN + i) - y[trainN + i]).abs();
        act += y[trainN + i];
      }
      wape = err / math.max(act, 1.0);
    }

    final Confidence confidence;
    if (wape == null) {
      confidence = Confidence.low;
    } else if (wape <= 0.45) {
      confidence = Confidence.high;
    } else if (wape <= 0.8) {
      confidence = Confidence.medium;
    } else {
      confidence = Confidence.low;
    }

    // Kapan stok habis.
    double? daysLeft;
    if (p.stock <= 0) {
      daysLeft = 0.0;
    } else {
      var remaining = p.stock.toDouble();
      for (var k = 0; k < _horizon; k++) {
        final d = preds[k];
        if (d > 0 && remaining <= d) {
          daysLeft = k + remaining / d;
          break;
        }
        remaining -= d;
      }
    }

    // Target stok dan saran restock.
    final planning = math.min(c.planningDays, _horizon);
    var horizonDemand = 0.0;
    for (var k = 0; k < planning; k++) {
      horizonDemand += preds[k];
    }
    final safety =
        c.serviceZ * model.sigma * math.sqrt(c.leadTimeDays.toDouble());
    final target = math.max(horizonDemand + safety, p.minStock * 2.0);
    var qty = math.max(0, ((target - p.stock) - 1e-9).ceil());

    final lead = c.leadTimeDays;
    final Urgency urgency;
    if (p.stock <= 0 || (daysLeft != null && daysLeft <= lead)) {
      urgency = Urgency.critical;
    } else if ((daysLeft != null && daysLeft <= lead + 7) ||
        p.stock <= p.minStock) {
      urgency = Urgency.soon;
    } else {
      urgency = Urgency.ok;
    }
    if (urgency == Urgency.ok) qty = 0;

    return ProductForecast(
      product: p,
      history: y,
      next7: next7,
      recentAvg: recentAvg,
      predictedDaily: predictedDaily,
      weekTotal: weekTotal,
      trendPct: trend,
      daysLeft: daysLeft,
      horizonDemand: horizonDemand,
      safetyStock: safety,
      targetStock: target,
      restockQty: qty,
      urgency: urgency,
      confidence: confidence,
      wape: wape,
      basedOnForecast: true,
      slow: predictedDaily < 0.1 && p.stock > p.minStock,
    );
  }

  // ------------------------------------------------------------------
  // Pelatihan model
  // ------------------------------------------------------------------

  static ({double a, double b}) _ols(List<double> v) {
    final n = v.length;
    if (n == 0) return (a: 0.0, b: 0.0);
    final tm = (n - 1) / 2.0;
    var vm = 0.0;
    for (final x in v) {
      vm += x;
    }
    vm /= n;
    var num = 0.0;
    var den = 0.0;
    for (var t = 0; t < n; t++) {
      num += (t - tm) * (v[t] - vm);
      den += (t - tm) * (t - tm);
    }
    final b = den > 0 ? num / den : 0.0;
    return (a: vm - b * tm, b: b);
  }

  static _Model _fit(List<double> y, int firstDow, double damping) {
    final n = y.length;
    var total = 0.0;
    for (final v in y) {
      total += v;
    }

    // 1) Faktor hari dalam minggu, dihitung terhadap garis tren agar tren
    //    tidak tercampur ke dalam pola mingguan.
    var s = List<double>.filled(7, 1.0);
    if (n >= 14 && total > 0) {
      final raw = _ols(y);
      final sy = List<double>.filled(7, 0.0);
      final st = List<double>.filled(7, 0.0);
      final cnt = List<int>.filled(7, 0);
      for (var t = 0; t < n; t++) {
        final d = (firstDow + t) % 7;
        sy[d] += y[t];
        st[d] += math.max(0.0, raw.a + raw.b * t);
        cnt[d]++;
      }
      final idx = List<double>.filled(7, 1.0);
      for (var d = 0; d < 7; d++) {
        if (cnt[d] == 0 || st[d] <= 1e-9) continue;
        final r = sy[d] / st[d];
        idx[d] = 1 + (r - 1) * cnt[d] / (cnt[d] + 1);
      }
      var mean = 0.0;
      for (final v in idx) {
        mean += v;
      }
      mean /= 7;
      s = idx.map((v) => v / mean).toList();
    }

    // 2) Regresi linear pada data yang sudah dibersihkan dari faktor hari.
    final z = List<double>.generate(n, (t) => y[t] / s[(firstDow + t) % 7]);
    final fit = _ols(z);

    // 3) Simpangan galat (untuk stok pengaman).
    var sse = 0.0;
    for (var t = 0; t < n; t++) {
      final f = math.max(0.0, fit.a + fit.b * t) * s[(firstDow + t) % 7];
      sse += (y[t] - f) * (y[t] - f);
    }
    final sigma = math.sqrt(sse / math.max(1, n - 2));

    return _Model(
      n: n,
      firstDow: firstDow,
      a: fit.a,
      b: fit.b,
      sigma: sigma,
      damping: damping,
      s: s,
    );
  }
}

// =====================================================================
// Data contoh (hanya di memori, tidak disimpan)
// =====================================================================

class DemoSales {
  DemoSales._();

  static const int days = 35;

  // Pola mingguan: Senin ... Minggu.
  static const List<double> _weekly = [0.8, 0.9, 1.0, 1.1, 1.5, 1.8, 0.6];

  static ({List<SaleRecord> sales, DateTime firstSaleAtUtc}) generate(
    List<ProductModel> products,
    DateTime nowUtc,
    AppZone zone, {
    int seed = 7,
  }) {
    final todayKey = ForecastService.dayKey(nowUtc, zone);
    final epoch = DateTime.utc(1970, 1, 1);
    DateTime noonOf(int key) => TimeService.toUtc(
          epoch.add(Duration(days: key, hours: 12)),
          zone,
        );

    final out = <SaleRecord>[];
    for (final p in products) {
      final h =
          p.id.codeUnits.fold<int>(seed, (a, c) => (a * 31 + c) & 0x7fffffff);
      final rnd = math.Random(h);
      final base = 0.8 + (h % 9) * 0.45; // 0,8 .. 4,4 per hari
      final trend = ((h ~/ 9) % 5 - 2) * 0.012; // -2,4% .. +2,4% per hari
      for (var d = days; d >= 1; d--) {
        final key = todayKey - d;
        final t = days - d;
        final lambda = math.max(0.0, base * (1 + trend * (t - days / 2))) *
            _weekly[ForecastService.dayOfWeek(key)];
        final noise = (rnd.nextDouble() - 0.5) * 2 * math.sqrt(lambda + 0.5);
        final qty = math.max(0, (lambda + noise).round());
        if (qty > 0) out.add(SaleRecord(p.id, noonOf(key), qty));
      }
    }
    return (sales: out, firstSaleAtUtc: noonOf(todayKey - days));
  }
}
