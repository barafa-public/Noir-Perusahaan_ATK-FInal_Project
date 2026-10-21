import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/services/currency_service.dart';

void main() {
  final rates = RateSnapshot(
    perUsd: const {'USD': 1.0, 'IDR': 18000.0, 'EUR': 0.9},
    fetchedAt: DateTime.utc(2026, 10, 21),
  );

  test('USD ke IDR dan sebaliknya', () {
    expect(rates.convert(100, 'USD', 'IDR'), 1800000);
    expect(rates.convert(1800000, 'IDR', 'USD'), closeTo(100, 1e-9));
  });

  test('IDR ke EUR lewat USD', () {
    expect(rates.convert(18000, 'IDR', 'EUR'), closeTo(0.9, 1e-9));
  });

  test('mata uang yang sama tidak berubah', () {
    expect(rates.convert(123.45, 'EUR', 'EUR'), closeTo(123.45, 1e-9));
  });

  test('mata uang tidak dikenal melempar CurrencyException', () {
    expect(() => rates.convert(1, 'USD', 'JPY'), throwsA(isA<CurrencyException>()));
  });

  test('format', () {
    expect(CurrencyService.format('IDR', 1804300), 'Rp 1.804.300');
    expect(CurrencyService.format('USD', 1234.5), 'US\$ 1.234,50');
    expect(CurrencyService.format('EUR', 0.5), '€ 0,50');
  });

  test('parseAmount', () {
    expect(CurrencyService.parseAmount('100000'), 100000);
    expect(CurrencyService.parseAmount('12,5'), 12.5);
    expect(CurrencyService.parseAmount('12.5'), 12.5);
    expect(CurrencyService.parseAmount(''), isNull);
  });
}