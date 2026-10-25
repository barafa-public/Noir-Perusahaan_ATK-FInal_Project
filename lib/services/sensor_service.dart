import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorReading {
  final double x;
  final double y;
  final double z;
  final DateTime at;

  const SensorReading(this.x, this.y, this.z, this.at);

  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

/// Cuplikan data sensor pada satu saat, plus nilai puncak sejak cuplikan
/// sebelumnya.
class SensorSnapshot {
  final DateTime takenAt;
  final SensorReading? accel; // m/s²
  final SensorReading? gyro; // rad/s
  final double peakAccel; // m/s²
  final double peakGyro; // rad/s

  const SensorSnapshot({
    required this.takenAt,
    required this.accel,
    required this.gyro,
    required this.peakAccel,
    required this.peakGyro,
  });
}

/// Mendeteksi goyangan: [requiredSpikes] hentakan di atas [thresholdG]
/// dalam [window]. Hentakan yang berdekatan (< [minSpikeGap]) dihitung satu,
/// dan setelah goyangan terdeteksi ada jeda [cooldown].
class ShakeDetector {
  static const double gravity = 9.80665;

  final double thresholdG;
  final int requiredSpikes;
  final Duration window;
  final Duration minSpikeGap;
  final Duration cooldown;

  ShakeDetector({
    this.thresholdG = 2.5,
    this.requiredSpikes = 2,
    this.window = const Duration(milliseconds: 800),
    this.minSpikeGap = const Duration(milliseconds: 120),
    this.cooldown = const Duration(milliseconds: 1500),
  });

  final List<DateTime> _spikes = [];
  DateTime? _lastShake;

  /// [magnitude] dalam m/s² (termasuk gravitasi). Mengembalikan true saat
  /// goyangan terdeteksi.
  bool onSample(double magnitude, DateTime now) {
    if (magnitude / gravity < thresholdG) return false;
    if (_spikes.isNotEmpty && now.difference(_spikes.last) < minSpikeGap) {
      return false;
    }

    _spikes.removeWhere((t) => now.difference(t) > window);
    _spikes.add(now);
    if (_spikes.length < requiredSpikes) return false;

    _spikes.clear();
    final last = _lastShake;
    if (last != null && now.difference(last) < cooldown) return false;
    _lastShake = now;
    return true;
  }

  void reset() {
    _spikes.clear();
    _lastShake = null;
  }
}

/// Mendeteksi putaran HP seperti memutar setir (sumbu Z gyroscope, rad/s).
/// Searah jarum jam = +1, berlawanan = -1, selain itu 0.
///
/// Satu putaran cepat melewati [threshold] dihitung satu langkah. Detektor
/// baru siap lagi setelah kecepatan turun di bawah [release] (putaran
/// berhenti), dan ada jeda [lockout] antar-langkah supaya gerakan kembali
/// ke posisi semula tidak dihitung sebagai langkah berlawanan.
class TwistDetector {
  final double threshold;
  final double release;
  final Duration lockout;

  TwistDetector({
    this.threshold = 2.0,
    this.release = 0.7,
    this.lockout = const Duration(milliseconds: 450),
  });

  bool _armed = true;
  DateTime? _last;

  /// [rate]: kecepatan sudut sumbu Z dalam rad/s. Pada konvensi Android,
  /// nilai negatif berarti searah jarum jam jika HP dilihat dari depan.
  int onSample(double rate, DateTime now) {
    final a = rate.abs();
    if (a < release) {
      _armed = true;
      return 0;
    }
    if (!_armed || a < threshold) return 0;

    final last = _last;
    if (last != null && now.difference(last) < lockout) return 0;

    _armed = false;
    _last = now;
    return rate < 0 ? 1 : -1;
  }

  void reset() {
    _armed = true;
    _last = null;
  }
}

/// Membaca accelerometer dan gyroscope. Satu instance per layar:
/// panggil [start] saat layar tampil dan [dispose] saat ditutup.
class SensorService {
  static const _uiInterval = Duration(milliseconds: 100);

  final ValueNotifier<SensorReading?> accel = ValueNotifier(null);
  final ValueNotifier<SensorReading?> gyro = ValueNotifier(null);
  final ValueNotifier<String?> accelError = ValueNotifier(null);
  final ValueNotifier<String?> gyroError = ValueNotifier(null);

  /// Nonaktifkan untuk mematikan deteksi goyang.
  bool shakeEnabled = true;

  /// Aktifkan untuk mendeteksi putaran HP (aliran [twists]).
  bool twistEnabled = false;

  final ShakeDetector _detector = ShakeDetector();
  final TwistDetector _twist = TwistDetector();
  final StreamController<void> _shakes = StreamController<void>.broadcast();
  final StreamController<int> _twists = StreamController<int>.broadcast();

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  DateTime _lastAccelUi = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastGyroUi = DateTime.fromMillisecondsSinceEpoch(0);
  double _peakAccel = 0;
  double _peakGyro = 0;
  bool _disposed = false;

  Stream<void> get shakes => _shakes.stream;

  /// +1 = putar searah jarum jam, -1 = berlawanan.
  Stream<int> get twists => _twists.stream;
  bool get running => _accelSub != null;

  void start() {
    if (_disposed || running) return;
    accelError.value = null;
    gyroError.value = null;
    _detector.reset();
    _twist.reset();

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      _onAccel,
      onError: (Object _) {
        accelError.value = 'Accelerometer tidak tersedia di perangkat ini.';
      },
    );

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      _onGyro,
      onError: (Object _) {
        gyroError.value = 'Gyroscope tidak tersedia di perangkat ini.';
      },
    );
  }

  void stop() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
  }

  void _onAccel(AccelerometerEvent e) {
    final now = DateTime.now();
    final reading = SensorReading(e.x, e.y, e.z, now);
    final mag = reading.magnitude;
    if (mag > _peakAccel) _peakAccel = mag;

    if (shakeEnabled && _detector.onSample(mag, now) && !_shakes.isClosed) {
      _shakes.add(null);
    }

    // Deteksi memakai semua sampel; tampilan dibatasi agar tidak boros.
    if (now.difference(_lastAccelUi) >= _uiInterval) {
      _lastAccelUi = now;
      accel.value = reading;
    }
  }

  void _onGyro(GyroscopeEvent e) {
    final now = DateTime.now();
    final reading = SensorReading(e.x, e.y, e.z, now);
    if (reading.magnitude > _peakGyro) _peakGyro = reading.magnitude;

    if (twistEnabled) {
      final step = _twist.onSample(e.z, now);
      if (step != 0 && !_twists.isClosed) _twists.add(step);
    }

    if (now.difference(_lastGyroUi) >= _uiInterval) {
      _lastGyroUi = now;
      gyro.value = reading;
    }
  }

  /// Mengambil cuplikan sekarang dan mengosongkan nilai puncak.
  SensorSnapshot capture() {
    final snap = SensorSnapshot(
      takenAt: DateTime.now(),
      accel: accel.value,
      gyro: gyro.value,
      peakAccel: _peakAccel,
      peakGyro: _peakGyro,
    );
    _peakAccel = 0;
    _peakGyro = 0;
    return snap;
  }

  void dispose() {
    _disposed = true;
    stop();
    _shakes.close();
    _twists.close();
    accel.dispose();
    gyro.dispose();
    accelError.dispose();
    gyroError.dispose();
  }
}
