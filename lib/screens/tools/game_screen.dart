import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/auth_service.dart';
import '../../services/db_helper.dart';

// =====================================================================
// Logika permainan (tanpa UI, mudah diuji)
// =====================================================================

class GameItem {
  final String name;
  final String category;
  final int price; // rupiah

  const GameItem(this.name, this.category, this.price);
}

class PriceQuestion {
  final GameItem item;
  final List<int> options; // sudah diacak; salah satunya harga sebenarnya

  const PriceQuestion({required this.item, required this.options});

  int get correctIndex => options.indexOf(item.price);
}

class PriceGame {
  PriceGame._();

  static const int rounds = 10;
  static const int secondsPerRound = 15;
  static const int optionCount = 4;

  /// Dipakai jika katalog produk masih terlalu sedikit.
  static const List<GameItem> fallbackItems = [
    GameItem('Pulpen Hitam', 'Alat Tulis', 3500),
    GameItem('Pensil 2B', 'Alat Tulis', 2500),
    GameItem('Penghapus', 'Alat Tulis', 2000),
    GameItem('Penggaris 30 cm', 'Alat Tulis', 4000),
    GameItem('Spidol Whiteboard', 'Alat Tulis', 9000),
    GameItem('Highlighter', 'Alat Tulis', 8500),
    GameItem('Buku Tulis 38 Lembar', 'Kertas', 4500),
    GameItem('Kertas A4 70 gr (rim)', 'Kertas', 52000),
    GameItem('Sticky Notes', 'Kertas', 6500),
    GameItem('Map Plastik', 'Map & Arsip', 3000),
    GameItem('Binder Clip', 'Map & Arsip', 5000),
    GameItem('Stapler Kecil', 'Perlengkapan Meja', 12000),
    GameItem('Isi Staples No. 10', 'Perlengkapan Meja', 3000),
    GameItem('Gunting', 'Perlengkapan Meja', 8000),
    GameItem('Lem Stick', 'Perlengkapan Meja', 6000),
    GameItem('Correction Tape', 'Alat Tulis', 7000),
  ];

  /// Kelipatan pembulatan untuk pilihan jawaban.
  static int step(int price) => price < 10000
      ? 500
      : price < 100000
          ? 1000
          : 5000;

  static int roundTo(double value, int step) =>
      max(step, (value / step).round() * step);

  /// Satu harga benar + tiga harga salah yang masuk akal, diacak. Pilihan
  /// selalu unik dan positif.
  static List<int> buildOptions(int price, Random rnd) {
    final s = step(price);
    final wrong = <int>[];
    final seen = <int>{price};

    void tryAdd(double factor) {
      if (wrong.length >= optionCount - 1) return;
      final v = roundTo(price * factor, s);
      if (v > 0 && seen.add(v)) wrong.add(v);
    }

    final primary = <double>[0.5, 0.75, 1.25, 1.5, 2.0]..shuffle(rnd);
    for (final f in primary) {
      tryAdd(f);
    }
    if (wrong.length < optionCount - 1) {
      final extra = <double>[0.4, 0.6, 0.9, 1.1, 1.8, 2.5, 3.0]..shuffle(rnd);
      for (final f in extra) {
        tryAdd(f);
      }
    }
    // Harga sangat kecil: tambahkan kelipatan di atasnya.
    var k = 1;
    while (wrong.length < optionCount - 1) {
      final v = price + k * s;
      if (seen.add(v)) wrong.add(v);
      k++;
    }

    return <int>[price, ...wrong]..shuffle(rnd);
  }

  /// Memilih hingga [count] produk berbeda (nama unik, harga > 0) sebagai soal.
  static List<PriceQuestion> buildQuestions(
    List<GameItem> pool,
    Random rnd, {
    int count = rounds,
  }) {
    final names = <String>{};
    final unique = <GameItem>[];
    for (final item in pool) {
      if (item.price > 0 && names.add(item.name.trim().toLowerCase())) {
        unique.add(item);
      }
    }
    unique.shuffle(rnd);
    return unique
        .take(count)
        .map((i) => PriceQuestion(item: i, options: buildOptions(i.price, rnd)))
        .toList();
  }

  /// 100 poin + bonus waktu (sisa detik × 4, maksimal 60) + bonus beruntun
  /// (10 per jawaban beruntun sejak yang kedua, maksimal 50).
  /// [streak] = jumlah jawaban benar beruntun termasuk yang ini.
  static int scoreFor({required int remainingMs, required int streak}) {
    final ms = max(0, min(remainingMs, secondsPerRound * 1000));
    final timeBonus = ms * 4 ~/ 1000;
    final streakBonus = max(0, min(streak, 6) - 1) * 10;
    return 100 + timeBonus + streakBonus;
  }
}

// =====================================================================
// Skor tertinggi lokal (per akun)
// =====================================================================

class GameScoreStore {
  final String userId;

  const GameScoreStore([this.userId = 'anon']);

  String get _key => 'game_high_score_$userId';

  Future<int> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_key) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Menyimpan [score] jika LEBIH TINGGI dari rekor. Mengembalikan true
  /// bila rekor baru tercipta.
  Future<bool> saveIfHigher(int score) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_key) ?? 0;
      if (score > current) {
        await prefs.setInt(_key, score);
        return true;
      }
    } catch (_) {}
    return false;
  }
}

// =====================================================================
// Layar
// =====================================================================

enum _Phase { loading, intro, playing, result }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final GameScoreStore _store =
      GameScoreStore(AuthService.instance.user?.id ?? 'anon');
  final Random _rnd = Random();

  _Phase _phase = _Phase.loading;
  List<GameItem> _pool = const [];
  bool _usingFallback = false;
  int _highScore = 0;

  List<PriceQuestion> _questions = const [];
  int _round = 0;
  int _score = 0;
  int _correct = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _lastGain = 0;
  bool _newRecord = false;

  /// null = belum dijawab; -1 = waktu habis; selain itu indeks pilihan.
  int? _picked;

  Timer? _ticker;
  DateTime _deadline = DateTime.now();
  int _remainingMs = PriceGame.secondsPerRound * 1000;
  Duration? _pausedLeft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_phase != _Phase.playing || _picked != null) return;
    if (state == AppLifecycleState.paused && _ticker != null) {
      _pausedLeft = _deadline.difference(DateTime.now());
      _ticker?.cancel();
      _ticker = null;
    } else if (state == AppLifecycleState.resumed && _pausedLeft != null) {
      _deadline = DateTime.now().add(_pausedLeft!);
      _pausedLeft = null;
      _startTicker();
    }
  }

  Future<void> _init() async {
    var items = <GameItem>[];
    try {
      final products = await DbHelper.instance.getProducts();
      items = products
          .where((p) => p.price > 0)
          .map((p) => GameItem(p.name, p.category, p.price))
          .toList();
    } catch (_) {}

    final distinct = items.map((i) => i.name.toLowerCase()).toSet().length;
    final usingFallback = distinct < 5;
    final high = await _store.load();
    if (!mounted) return;
    setState(() {
      _pool = usingFallback ? PriceGame.fallbackItems : items;
      _usingFallback = usingFallback;
      _highScore = high;
      _phase = _Phase.intro;
    });
  }

  // ------------------------------------------------------------------
  // Alur permainan
  // ------------------------------------------------------------------

  void _start() {
    final questions = PriceGame.buildQuestions(_pool, _rnd);
    if (questions.isEmpty) return;
    setState(() {
      _questions = questions;
      _round = 0;
      _score = 0;
      _correct = 0;
      _streak = 0;
      _bestStreak = 0;
      _lastGain = 0;
      _newRecord = false;
      _phase = _Phase.playing;
    });
    _beginRound();
  }

  void _beginRound() {
    _ticker?.cancel();
    _pausedLeft = null;
    _deadline = DateTime.now().add(
      const Duration(seconds: PriceGame.secondsPerRound),
    );
    setState(() {
      _picked = null;
      _lastGain = 0;
      _remainingMs = PriceGame.secondsPerRound * 1000;
    });
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final left = _deadline.difference(DateTime.now()).inMilliseconds;
      if (left <= 0) {
        _answer(-1); // waktu habis
      } else if (mounted) {
        setState(() => _remainingMs = left);
      }
    });
  }

  void _answer(int index) {
    if (_picked != null || _phase != _Phase.playing) return;
    _ticker?.cancel();
    _ticker = null;

    final q = _questions[_round];
    final isCorrect = index == q.correctIndex;
    final left = max(0, _deadline.difference(DateTime.now()).inMilliseconds);

    setState(() {
      _picked = index;
      _remainingMs = isCorrect ? left : 0;
      if (isCorrect) {
        _streak++;
        _correct++;
        _bestStreak = max(_bestStreak, _streak);
        _lastGain = PriceGame.scoreFor(remainingMs: left, streak: _streak);
        _score += _lastGain;
      } else {
        _streak = 0;
        _lastGain = 0;
      }
    });
  }

  Future<void> _next() async {
    if (_round + 1 < _questions.length) {
      setState(() => _round++);
      _beginRound();
      return;
    }

    final record = await _store.saveIfHigher(_score);
    final high = await _store.load();
    if (!mounted) return;
    setState(() {
      _newRecord = record;
      _highScore = high;
      _phase = _Phase.result;
    });
  }

  // ------------------------------------------------------------------
  // Tampilan
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tebak Harga ATK')),
      body: switch (_phase) {
        _Phase.loading => const Center(
            child: CircularProgressIndicator(color: AppColors.yellow),
          ),
        _Phase.intro => _intro(),
        _Phase.playing => _playing(),
        _Phase.result => _result(),
      },
    );
  }

  Widget _intro() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.sell_rounded, size: 72, color: AppColors.yellow),
        const SizedBox(height: 16),
        const Text(
          'Tebak Harga ATK',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Berapa harga barang ini? Pilih jawaban yang benar sebelum waktu habis.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rule(Icons.quiz_rounded,
                    '${PriceGame.rounds} soal, 4 pilihan harga'),
                _rule(Icons.timer_rounded,
                    '${PriceGame.secondsPerRound} detik per soal'),
                _rule(Icons.bolt_rounded,
                    'Makin cepat dan beruntun, makin tinggi skor'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.emoji_events_rounded, color: AppColors.yellow),
            title: const Text('Skor tertinggi'),
            trailing: Text(
              '$_highScore',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _usingFallback
              ? 'Katalog produk masih sedikit, jadi soal memakai daftar ATK contoh.'
              : 'Soal diambil dari ${_pool.length} produk di katalog toko Anda.',
          textAlign: TextAlign.center,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Mulai'),
        ),
      ],
    );
  }

  Widget _rule(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.yellow),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Widget _playing() {
    final q = _questions[_round];
    final answered = _picked != null;
    final isLast = _round + 1 >= _questions.length;
    final low = _remainingMs <= 5000;

    String feedback = '';
    Color feedbackColor = AppColors.textSecondary;
    if (answered) {
      if (_picked == q.correctIndex) {
        feedback = 'Benar! +$_lastGain poin'
            '${_streak >= 2 ? '  ·  beruntun $_streak' : ''}';
        feedbackColor = AppColors.success;
      } else {
        feedback = (_picked == -1 ? 'Waktu habis. ' : 'Salah. ') +
            'Harga sebenarnya ${Formatters.rupiah(q.item.price)}';
        feedbackColor = AppColors.error;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Soal ${_round + 1}/${_questions.length}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 18, color: AppColors.yellow),
                const SizedBox(width: 4),
                Text(
                  '$_score',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _remainingMs / (PriceGame.secondsPerRound * 1000),
            minHeight: 8,
            color: low ? AppColors.error : AppColors.yellow,
            backgroundColor: AppColors.border,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              children: [
                const Icon(Icons.inventory_2_rounded,
                    size: 40, color: AppColors.yellow),
                const SizedBox(height: 12),
                Text(
                  q.item.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  q.item.category,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                const Text('Berapa harganya?'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < q.options.length; i++) _option(i, q),
        if (answered) ...[
          const SizedBox(height: 4),
          Text(
            feedback,
            textAlign: TextAlign.center,
            style: TextStyle(color: feedbackColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _next,
            child: Text(isLast ? 'Lihat hasil' : 'Lanjut'),
          ),
        ],
      ],
    );
  }

  Widget _option(int i, PriceQuestion q) {
    final answered = _picked != null;
    final isCorrect = i == q.correctIndex;
    final isPicked = _picked == i;

    Color border = AppColors.border;
    Color bg = AppColors.surface;
    Color fg = AppColors.white;
    IconData? icon;

    if (answered) {
      if (isCorrect) {
        border = AppColors.success;
        bg = AppColors.success.withValues(alpha: 0.15);
        icon = Icons.check_circle_rounded;
      } else if (isPicked) {
        border = AppColors.error;
        bg = AppColors.error.withValues(alpha: 0.15);
        icon = Icons.cancel_rounded;
      } else {
        fg = AppColors.textSecondary;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: border,
            width: (answered && (isCorrect || isPicked)) ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: answered ? null : () => _answer(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    Formatters.rupiah(q.options[i]),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
                if (icon != null)
                  Icon(
                    icon,
                    color: isCorrect ? AppColors.success : AppColors.error,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _verdict {
    final total = _questions.length;
    if (_correct >= total * 0.9) return 'Pakar harga ATK!';
    if (_correct >= total * 0.6) return 'Lumayan jago!';
    if (_correct >= total * 0.3) return 'Terus berlatih!';
    return 'Coba lagi, pasti bisa!';
  }

  Widget _result() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.emoji_events_rounded,
            size: 72, color: AppColors.yellow),
        const SizedBox(height: 12),
        Text(
          _verdict,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '$_score',
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              color: AppColors.yellow,
            ),
          ),
        ),
        const Center(
          child: Text('poin', style: TextStyle(color: AppColors.textSecondary)),
        ),
        if (_newRecord) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.yellow.withValues(alpha: 0.5)),
            ),
            child: const Text(
              'Rekor baru!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.yellow, fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _stat('Jawaban benar', '$_correct dari ${_questions.length}'),
                _stat('Beruntun terbaik', '$_bestStreak'),
                _stat('Skor tertinggi', '$_highScore'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Main lagi'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Selesai'),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );
}
