// Uji alur pesanan end-to-end terhadap Edge Function yang sudah ter-deploy
// (PBI-07.4). Skrip Dart murni, tanpa paket tambahan.
//
// Jalankan dari folder proyek (yang berisi .env):
//   dart tool/order_flow_test.dart <username_internal> <password_internal>
//
// Yang dilakukan:
//  - login internal, mendaftarkan 1 akun Customer uji (username qa_...)
//  - memilih 1 produk, mencatat stok awal, lalu menguji alur
//    Selesai, Batalkan (sebelum/sesudah diproses), stok kurang, dan hak akses
//  - mengembalikan stok produk ke nilai awal di akhir
//
// Sisa data uji (akun qa_* dan pesanannya) tidak dihapus otomatis;
// lihat query pembersihan di dokumentasi Batch.

import 'dart:convert';
import 'dart:io';

late String _base;
late String _key;
int _passed = 0;
int _failed = 0;

void check(String name, bool ok, [String detail = '']) {
  if (ok) {
    _passed++;
    stdout.writeln('  PASS  $name');
  } else {
    _failed++;
    stdout.writeln('  FAIL  $name${detail.isEmpty ? '' : '  -> $detail'}');
  }
}

class Res {
  final int status;
  final Map<String, dynamic> body;
  Res(this.status, this.body);

  String get error => (body['error'] ?? '').toString();
  String get code => (body['code'] ?? '').toString();

  Map<String, dynamic> get order =>
      (body['order'] as Map<String, dynamic>?) ?? const {};
  String get orderStatus => (order['status'] ?? '').toString();

  @override
  String toString() => 'HTTP $status $error ${code.isEmpty ? '' : '[$code]'}';
}

Future<Res> call(
  String method,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('$_base$path'));
    req.headers.set('apikey', _key);
    req.headers.set('Content-Type', 'application/json');
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (method != 'GET') req.add(utf8.encode(jsonEncode(body ?? {})));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();

    var data = <String, dynamic>{};
    try {
      final d = jsonDecode(text);
      if (d is Map<String, dynamic>) data = d;
    } catch (_) {}
    return Res(res.statusCode, data);
  } finally {
    client.close();
  }
}

Map<String, String> readEnv() {
  final f = File('.env');
  if (!f.existsSync()) {
    stderr.writeln('.env tidak ditemukan. Jalankan dari folder proyek.');
    exit(2);
  }
  final m = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 0) continue;
    m[t.substring(0, i).trim()] = t
        .substring(i + 1)
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '');
  }
  return m;
}

Future<int> stockOf(String token, String productId) async {
  final r = await call('GET', '/products', token: token);
  final list = (r.body['products'] as List).cast<Map<String, dynamic>>();
  final p = list.firstWhere((p) => p['id'] == productId);
  return (p['stock'] as num).toInt();
}

Future<String> createOrder(
  String customerToken,
  String productId,
  int qty,
) async {
  final r = await call(
    'POST',
    '/orders',
    token: customerToken,
    body: {
      'items': [
        {'product_id': productId, 'qty': qty},
      ],
    },
  );
  if (r.status != 201) {
    throw 'Gagal membuat pesanan uji (qty $qty): $r';
  }
  return r.order['id'] as String;
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Pemakaian: dart tool/order_flow_test.dart <username_internal> <password_internal>',
    );
    exit(2);
  }

  final env = readEnv();
  _base = (env['BACKEND_URL'] ?? '').replaceAll(RegExp(r'/+$'), '');
  _key = env['BACKEND_PUBLISHABLE_KEY'] ?? '';
  if (_base.isEmpty || _key.isEmpty) {
    stderr.writeln('BACKEND_URL / BACKEND_PUBLISHABLE_KEY kosong di .env');
    exit(2);
  }

  // --- persiapan -------------------------------------------------------
  final a = await call(
    'POST',
    '/auth/login',
    body: {'username': args[0], 'password': args[1]},
  );
  if (a.status != 200) {
    stderr.writeln('Login internal gagal: $a');
    exit(2);
  }
  final admin = a.body['token'] as String;

  final uname = 'qa_${DateTime.now().millisecondsSinceEpoch % 100000000000}';
  final c = await call(
    'POST',
    '/auth/register',
    body: {
      'username': uname,
      'password': 'QaTest#2026pw',
      'full_name': 'QA Tester',
    },
  );
  if (c.status != 201) {
    stderr.writeln('Registrasi Customer uji gagal: $c');
    exit(2);
  }
  final cust = c.body['token'] as String;
  stdout.writeln('Akun uji: $uname');

  // Produk uji: stok 6..500 (qty pesanan maksimal 1000 per produk).
  final pr = await call('GET', '/products', token: admin);
  final products = (pr.body['products'] as List).cast<Map<String, dynamic>>();
  final candidates = products.where((p) {
    final s = (p['stock'] as num).toInt();
    return s >= 6 && s <= 500;
  }).toList();
  if (candidates.isEmpty) {
    stderr.writeln('Tidak ada produk dengan stok 6-500 untuk diuji.');
    exit(2);
  }
  final pid = candidates.first['id'] as String;
  final s0 = (candidates.first['stock'] as num).toInt();
  stdout.writeln('Produk uji: ${candidates.first['name']} (stok awal $s0)\n');

  try {
    // --- 1. Alur sampai Selesai ----------------------------------------
    stdout.writeln('1. Dipesan -> Diproses -> Selesai');
    final o1 = await createOrder(cust, pid, 2);
    check(
      'stok belum berubah saat pesanan dibuat',
      await stockOf(admin, pid) == s0,
    );

    var r = await call('POST', '/orders/$o1/process', token: admin);
    check(
      'proses berhasil, status Diproses',
      r.status == 200 && r.orderStatus == 'Diproses',
      '$r',
    );
    check('stok berkurang 2', await stockOf(admin, pid) == s0 - 2);

    r = await call('POST', '/orders/$o1/process', token: admin);
    check(
      'proses ulang ditolak 409 INVALID_STATUS',
      r.status == 409 && r.code == 'INVALID_STATUS',
      '$r',
    );
    check(
      'proses ulang tidak mengurangi stok lagi',
      await stockOf(admin, pid) == s0 - 2,
    );

    r = await call('POST', '/orders/$o1/complete', token: admin);
    check(
      'selesai berhasil, status Selesai',
      r.status == 200 && r.orderStatus == 'Selesai',
      '$r',
    );
    check('stok tetap setelah selesai', await stockOf(admin, pid) == s0 - 2);

    r = await call(
      'POST',
      '/orders/$o1/cancel',
      token: admin,
      body: {'reason': 'Coba batalkan'},
    );
    check(
      'batal setelah Selesai ditolak 409',
      r.status == 409 && r.code == 'INVALID_STATUS',
      '$r',
    );

    // --- 2. Batal setelah diproses -------------------------------------
    stdout.writeln('\n2. Batal setelah Diproses (stok kembali)');
    final o2 = await createOrder(cust, pid, 3);
    r = await call('POST', '/orders/$o2/process', token: admin);
    check('diproses', r.status == 200 && r.orderStatus == 'Diproses', '$r');
    check('stok berkurang 3 lagi', await stockOf(admin, pid) == s0 - 5);

    r = await call(
      'POST',
      '/orders/$o2/cancel',
      token: admin,
      body: {'reason': 'Barang rusak'},
    );
    check(
      'batal berhasil, status Dibatalkan',
      r.status == 200 && r.orderStatus == 'Dibatalkan',
      '$r',
    );
    check('stok kembali', await stockOf(admin, pid) == s0 - 2);

    r = await call('GET', '/orders/$o2', token: cust);
    check(
      'Customer melihat alasan pembatalan',
      r.status == 200 && r.order['cancel_reason'] == 'Barang rusak',
      '$r',
    );

    // --- 3. Batal sebelum diproses -------------------------------------
    stdout.writeln('\n3. Batal sebelum Diproses (stok tidak berubah)');
    final o3 = await createOrder(cust, pid, 1);
    r = await call(
      'POST',
      '/orders/$o3/cancel',
      token: admin,
      body: {'reason': ''},
    );
    check('batal tanpa alasan ditolak 422', r.status == 422, '$r');
    r = await call(
      'POST',
      '/orders/$o3/cancel',
      token: admin,
      body: {'reason': 'Pelanggan berubah pikiran'},
    );
    check(
      'batal berhasil',
      r.status == 200 && r.orderStatus == 'Dibatalkan',
      '$r',
    );
    check('stok tidak berubah', await stockOf(admin, pid) == s0 - 2);

    r = await call('POST', '/orders/$o3/complete', token: admin);
    check('selesai pada pesanan batal ditolak 409', r.status == 409, '$r');

    // --- 4. Validasi stok atomik ----------------------------------------
    stdout.writeln('\n4. Stok tidak cukup saat diproses');
    final s = await stockOf(admin, pid);
    final a4 = await createOrder(cust, pid, s);
    final b4 = await createOrder(cust, pid, s); // lolos: stok belum dikurangi
    r = await call('POST', '/orders/$a4/process', token: admin);
    check('pesanan A diproses', r.status == 200, '$r');
    check('stok menjadi 0', await stockOf(admin, pid) == 0);

    r = await call('POST', '/orders/$b4/process', token: admin);
    check(
      'pesanan B ditolak 409 INSUFFICIENT_STOCK',
      r.status == 409 && r.code == 'INSUFFICIENT_STOCK',
      '$r',
    );
    r = await call('GET', '/orders/$b4', token: admin);
    check('pesanan B tetap Dipesan', r.orderStatus == 'Dipesan', '$r');
    check('stok tetap 0 (tidak minus)', await stockOf(admin, pid) == 0);

    await call(
      'POST',
      '/orders/$a4/cancel',
      token: admin,
      body: {'reason': 'Uji stok'},
    );
    await call(
      'POST',
      '/orders/$b4/cancel',
      token: admin,
      body: {'reason': 'Uji stok'},
    );
    check('stok pulih setelah A dibatalkan', await stockOf(admin, pid) == s);

    // --- 5. Hak akses ---------------------------------------------------
    stdout.writeln('\n5. Hak akses');
    final o5 = await createOrder(cust, pid, 1);
    r = await call('POST', '/orders/$o5/process', token: cust);
    check('Customer tidak boleh proses (403)', r.status == 403, '$r');
    r = await call(
      'POST',
      '/orders/$o5/cancel',
      token: cust,
      body: {'reason': 'Customer coba batal'},
    );
    check(
      'Customer tidak boleh batalkan lewat endpoint ini (403)',
      r.status == 403,
      '$r',
    );
    r = await call(
      'POST',
      '/orders',
      token: admin,
      body: {
        'items': [
          {'product_id': pid, 'qty': 1},
        ],
      },
    );
    check(
      'User internal tidak boleh membuat pesanan (403)',
      r.status == 403,
      '$r',
    );
    r = await call('GET', '/orders?status=Dipesan', token: admin);
    final ids = ((r.body['orders'] as List?) ?? const [])
        .map((e) => (e as Map<String, dynamic>)['id'])
        .toList();
    check('daftar internal memuat pesanan Dipesan', ids.contains(o5), '$r');
    r = await call('GET', '/orders?status=Salah', token: admin);
    check('filter status tidak valid ditolak 422', r.status == 422, '$r');
    await call(
      'POST',
      '/orders/$o5/cancel',
      token: admin,
      body: {'reason': 'Pembersihan uji'},
    );
  } catch (e) {
    _failed++;
    stdout.writeln('  ERROR $e');
  } finally {
    // Kembalikan stok ke nilai awal (pesanan Selesai di uji 1 memakai 2 unit).
    final r = await call(
      'POST',
      '/products/$pid',
      token: admin,
      body: {'stock': s0},
    );
    stdout.writeln(
      '\nStok produk uji dikembalikan ke $s0: ${r.status == 200 ? 'ok' : 'GAGAL ($r)'}',
    );
  }

  stdout.writeln('\nHasil: $_passed lulus, $_failed gagal');
  exit(_failed == 0 ? 0 : 1);
}
