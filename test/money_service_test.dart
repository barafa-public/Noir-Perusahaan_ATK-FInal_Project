import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/services/currency_service.dart';
import 'package:noir_final_project/services/money_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

RateSnapshot _rates() => RateSnapshot(
      perUsd: const {'USD': 1.0, 'IDR': 16000.0, 'EUR': 0.8},
      fetchedAt: DateTime.now().toUtc(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('format', () {
    test('IDR tidak berubah', () {
      final m = MoneyService(code: 'IDR', rates: _rates());
      expect(m.format(52000), 'Rp 52.000');
      expect(m.format(-1500), '-Rp 1.500');
    });

    test('USD dan EUR memakai kurs', () {
      final usd = MoneyService(code: 'USD', rates: _rates());
      expect(usd.format(16000), 'US\$ 1,00');
      expect(usd.format(52000), 'US\$ 3,25');
      expect(usd.format(160000000), 'US\$ 10.000,00');
      final eur = MoneyService(code: 'EUR', rates: _rates());
      expect(eur.format(16000), '€ 0,80');
    });

    test('tanpa kurs, jatuh kembali ke Rupiah', () {
      final m = MoneyService(code: 'USD');
      expect(m.isConverted, isFalse);
      expect(m.format(16000), 'Rp 16.000');
    });
  });

  group('setCurrency', () {
    test('IDR tidak memanggil jaringan', () async {
      var calls = 0;
      final m = MoneyService(fetcher: () async {
        calls++;
        return _rates();
      });
      await m.setCurrency('IDR');
      expect(calls, 0);
    });

    test('mengambil kurs, mengganti kode, memberi tahu pendengar', () async {
      final m = MoneyService(fetcher: () async => _rates());
      var notified = 0;
      m.addListener(() => notified++);
      await m.setCurrency('USD');
      expect(m.code, 'USD');
      expect(m.isConverted, isTrue);
      expect(notified, 1);
    });

    test('gagal tanpa kurs tersimpan: kode tidak berubah', () async {
      final m = MoneyService(
        fetcher: () async => throw const CurrencyException('offline'),
      );
      await expectLater(
          m.setCurrency('USD'), throwsA(isA<CurrencyException>()));
      expect(m.code, 'IDR');
    });

    test('gagal tetapi ada kurs tersimpan: tetap berganti', () async {
      final m = MoneyService(
        rates: _rates(),
        fetcher: () async => throw const CurrencyException('offline'),
      );
      await m.setCurrency('EUR');
      expect(m.code, 'EUR');
      expect(m.format(16000), '€ 0,80');
    });

    test('kode tidak dikenal diabaikan', () async {
      final m = MoneyService(fetcher: () async => _rates());
      await m.setCurrency('JPY');
      expect(m.code, 'IDR');
    });

    test('pilihan tersimpan dan dimuat ulang', () async {
      final a = MoneyService(fetcher: () async => _rates());
      await a.setCurrency('USD');

      final b = MoneyService(loader: () async => _rates());
      await b.load();
      expect(b.code, 'USD');
      expect(b.format(16000), 'US\$ 1,00');
    });
  });
}
