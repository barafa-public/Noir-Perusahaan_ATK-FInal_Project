import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/services/geocoding_service.dart';
import 'package:noir_final_project/services/location_service.dart';

void main() {
  group('haversineMeters', () {
    test('titik sama = 0', () {
      expect(LocationService.haversineMeters(-6.2, 106.8, -6.2, 106.8), 0);
    });

    test('1 derajat bujur di khatulistiwa ≈ 111,2 km', () {
      final m = LocationService.haversineMeters(0, 0, 0, 1);
      expect(m, closeTo(111195, 100));
    });

    test('Jakarta ke Bandung ≈ 116 km', () {
      final m = LocationService.haversineMeters(
        -6.2088,
        106.8456,
        -6.9175,
        107.6191,
      );
      expect(m, closeTo(116237, 500));
    });

    test('simetris', () {
      final a = LocationService.haversineMeters(-6.2, 106.8, -7.8, 110.4);
      final b = LocationService.haversineMeters(-7.8, 110.4, -6.2, 106.8);
      expect(a, closeTo(b, 0.001));
    });
  });

  group('parseSearch', () {
    test('membaca daftar hasil', () {
      const body = '''[
        {"lat":"-6.9174639","lon":"107.6191228","name":"Bandung",
         "display_name":"Bandung, Jawa Barat, Indonesia"},
        {"lat":"-6.9","lon":"107.6","name":"",
         "display_name":"Alun-Alun, Bandung, Jawa Barat"},
        {"lat":"x","lon":"107.6","name":"Rusak","display_name":"Rusak"}
      ]''';
      final r = GeocodingService.parseSearch(body);
      expect(r.length, 2); // yang koordinatnya rusak dilewati
      expect(r[0].name, 'Bandung');
      expect(r[0].latitude, closeTo(-6.9174639, 1e-9));
      expect(r[1].name, 'Alun-Alun'); // dari bagian pertama display_name
    });

    test('hasil kosong', () {
      expect(GeocodingService.parseSearch('[]'), isEmpty);
    });

    test('format salah melempar GeocodingException', () {
      expect(
        () => GeocodingService.parseSearch('bukan json'),
        throwsA(isA<GeocodingException>()),
      );
    });
  });

  group('parseReverse', () {
    test('memakai name bila ada', () {
      expect(
        GeocodingService.parseReverse(
          '{"name":"Bandung","display_name":"Bandung, Jawa Barat"}',
        ),
        'Bandung',
      );
    });

    test('jatuh ke bagian pertama display_name', () {
      expect(
        GeocodingService.parseReverse(
          '{"name":"","display_name":"Cimahi, Jawa Barat, Indonesia"}',
        ),
        'Cimahi',
      );
    });

    test('error atau rusak = null', () {
      expect(GeocodingService.parseReverse('{"error":"Unable"}'), isNull);
      expect(GeocodingService.parseReverse('???'), isNull);
    });
  });
}
