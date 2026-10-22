import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/services/time_service.dart';

void main() {
  group('offset zona Indonesia', () {
    final utc = DateTime.utc(2026, 10, 21, 5, 0);

    test('WIB +7, WITA +8, WIT +9', () {
      expect(TimeService.toZone(utc, AppZone.wib).hour, 12);
      expect(TimeService.toZone(utc, AppZone.wita).hour, 13);
      expect(TimeService.toZone(utc, AppZone.wit).hour, 14);
    });

    test('melewati tengah malam', () {
      final w =
          TimeService.toZone(DateTime.utc(2026, 10, 21, 20, 0), AppZone.wib);
      expect(w.day, 22);
      expect(w.hour, 3);
    });
  });

  group('London (GMT/BST)', () {
    test('musim panas = BST (UTC+1)', () {
      final utc = DateTime.utc(2026, 7, 1, 11, 0);
      expect(TimeService.offsetMinutes(AppZone.london, utc), 60);
      expect(TimeService.abbreviation(AppZone.london, utc), 'BST');
      expect(TimeService.toZone(utc, AppZone.london).hour, 12);
    });

    test('musim dingin = GMT (UTC+0)', () {
      final utc = DateTime.utc(2026, 1, 15, 12, 0);
      expect(TimeService.offsetMinutes(AppZone.london, utc), 0);
      expect(TimeService.abbreviation(AppZone.london, utc), 'GMT');
    });

    test('batas awal BST: Minggu terakhir Maret 2026 (29 Mar) 01:00 UTC', () {
      expect(
        TimeService.offsetMinutes(
            AppZone.london, DateTime.utc(2026, 3, 29, 0, 59)),
        0,
      );
      expect(
        TimeService.offsetMinutes(
            AppZone.london, DateTime.utc(2026, 3, 29, 1, 0)),
        60,
      );
    });

    test('batas akhir BST: Minggu terakhir Oktober 2026 (25 Okt) 01:00 UTC',
        () {
      expect(
        TimeService.offsetMinutes(
            AppZone.london, DateTime.utc(2026, 10, 25, 0, 59)),
        60,
      );
      expect(
        TimeService.offsetMinutes(
            AppZone.london, DateTime.utc(2026, 10, 25, 1, 0)),
        0,
      );
    });
  });

  group('waktu dinding -> UTC', () {
    test('WIB 12.00 = 05.00 UTC', () {
      final utc =
          TimeService.toUtc(DateTime.utc(2026, 10, 21, 12, 0), AppZone.wib);
      expect(utc, DateTime.utc(2026, 10, 21, 5, 0));
    });

    test('London musim panas 12.00 = 11.00 UTC', () {
      final utc =
          TimeService.toUtc(DateTime.utc(2026, 7, 1, 12, 0), AppZone.london);
      expect(utc, DateTime.utc(2026, 7, 1, 11, 0));
    });

    test('bolak-balik konsisten di semua zona', () {
      final utc = DateTime.utc(2026, 5, 10, 8, 30);
      for (final z in AppZone.values) {
        final back = TimeService.toUtc(TimeService.toZone(utc, z), z);
        expect(back, utc, reason: z.name);
      }
    });
  });

  group('format', () {
    test('formatIso memakai zona yang diminta', () {
      expect(
        TimeService.instance
            .formatIso('2026-10-21T05:00:00.000Z', zone: AppZone.wib),
        '21 Okt 2026, 12.00 WIB',
      );
      expect(
        TimeService.instance
            .formatIso('2026-10-21T05:00:00.000Z', zone: AppZone.london),
        '21 Okt 2026, 06.00 BST',
      );
    });

    test('ISO tidak valid -> "-"', () {
      expect(TimeService.instance.formatIso('bukan tanggal'), '-');
    });
  });
  group('awal hari', () {
    test('WIB: 21 Okt 2026 05.00 UTC -> awal hari 20 Okt 17.00 UTC', () {
      final start = TimeService.startOfDayUtc(
        AppZone.wib,
        DateTime.utc(2026, 10, 21, 5, 0),
      );
      expect(start, DateTime.utc(2026, 10, 20, 17, 0));
    });

    test('WIT: sudah berganti hari lebih dulu dari WIB', () {
      // 21 Okt 16.00 UTC = 22 Okt 01.00 WIT
      final start = TimeService.startOfDayUtc(
        AppZone.wit,
        DateTime.utc(2026, 10, 21, 16, 0),
      );
      expect(start, DateTime.utc(2026, 10, 21, 15, 0));
    });

    test('London BST: awal hari = 23.00 UTC hari sebelumnya', () {
      final start = TimeService.startOfDayUtc(
        AppZone.london,
        DateTime.utc(2026, 7, 1, 12, 0),
      );
      expect(start, DateTime.utc(2026, 6, 30, 23, 0));
    });
  });
}
