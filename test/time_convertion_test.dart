import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/services/time_service.dart';

void main() {
  String hm(DateTime utc, AppZone z) =>
      '${TimeService.formatHm(TimeService.toZone(utc, z))} '
      '${TimeService.abbreviation(z, utc)}';

  test('formatHm dua digit', () {
    expect(TimeService.formatHm(DateTime.utc(2026, 1, 1, 5, 7)), '05.07');
  });

  test('11.27 WIB = 12.27 WITA = 13.27 WIT = 04.27 GMT (musim dingin)', () {
    final utc = DateTime.utc(2026, 12, 1, 4, 27);
    expect(hm(utc, AppZone.wib), '11.27 WIB');
    expect(hm(utc, AppZone.wita), '12.27 WITA');
    expect(hm(utc, AppZone.wit), '13.27 WIT');
    expect(hm(utc, AppZone.london), '04.27 GMT');
  });

  test('London musim panas memakai BST', () {
    final utc = DateTime.utc(2026, 7, 1, 4, 27);
    expect(hm(utc, AppZone.london), '05.27 BST');
  });

  test('jam input bisa berganti hari antarzona', () {
    final utc = DateTime.utc(2026, 12, 1, 16, 30); // 23.30 WIB
    final wib = TimeService.toZone(utc, AppZone.wib);
    final wita = TimeService.toZone(utc, AppZone.wita);
    expect(wib.day, 1);
    expect(wita.day, 2);
    expect(TimeService.formatHm(wita), '00.30');
  });
}
