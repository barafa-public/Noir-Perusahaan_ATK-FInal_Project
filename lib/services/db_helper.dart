import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product_model.dart';
import '../models/sale_model.dart';

/// Ringkasan stok untuk Beranda internal.
class StockSummary {
  final int total;
  final int low; // stok <= minimum (sudah termasuk yang habis)
  final int out; // stok 0

  const StockSummary({this.total = 0, this.low = 0, this.out = 0});
}

class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static const _dbName = 'noir.db';
  static const _dbVersion = 2;

  static const _effectiveStock = '''
    MAX(0, p.stock - COALESCE((
      SELECT SUM(s.qty) FROM sales s
      WHERE s.product_id = p.id AND s.synced = 0 AND s.sync_error IS NULL
    ), 0))
  ''';

  static const _productColumns =
      'p.id, p.sku, p.name, p.category, p.description, p.price, '
      'p.min_stock, p.is_active, p.updated_at, $_effectiveStock AS stock';

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        // Membuat skema database untuk instalasi baru.
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migrasi versi 1 ke versi 2:
        // Hapus tabel lama yang sudah tidak digunakan.
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS cart_items');
          await db.execute('DROP TABLE IF EXISTS order_status_cache');
        }
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ===================================================================
  // Produk (cache katalog; sumber kebenaran tetap di server)
  // ===================================================================

  /// Menerapkan perubahan dari server dalam satu transaksi:
  /// produk aktif di-upsert, produk nonaktif dihapus dari cache
  /// (beserta item keranjang dan penanda notifikasinya).
  Future<void> applyProductChanges(List<ProductModel> changes) async {
    if (changes.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final p in changes) {
        if (p.isActive) {
          batch.insert(
            'products',
            p.toDb(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          batch.delete('products', where: 'id = ?', whereArgs: [p.id]);
          batch.delete(
            'low_stock_alerts',
            where: 'product_id = ?',
            whereArgs: [p.id],
          );
        }
      }
      await batch.commit(noResult: true);
    });
  }

  /// Daftar produk (stok efektif), opsional dicari (nama/SKU) dan difilter kategori.
  Future<List<ProductModel>> getProducts({
    String? query,
    String? category,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      final esc = q
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      where.add(r"(p.name LIKE ? ESCAPE '\' OR p.sku LIKE ? ESCAPE '\')");
      args
        ..add('%$esc%')
        ..add('%$esc%');
    }
    if (category != null && category.isNotEmpty) {
      where.add('p.category = ?');
      args.add(category);
    }

    final rows = await db.rawQuery(
      'SELECT $_productColumns FROM products p'
      '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
      ' ORDER BY p.name COLLATE NOCASE ASC',
      args,
    );
    return rows.map(ProductModel.fromDb).toList();
  }

  Future<ProductModel?> getProduct(String id) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT $_productColumns FROM products p WHERE p.id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : ProductModel.fromDb(rows.first);
  }

  /// Total produk, jumlah stok menipis (<= minimum), dan jumlah habis.
  Future<StockSummary> getStockSummary() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total,
             COALESCE(SUM(CASE WHEN stock <= min_stock THEN 1 ELSE 0 END), 0) AS low,
             COALESCE(SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END), 0) AS out
      FROM (SELECT p.min_stock AS min_stock, $_effectiveStock AS stock
            FROM products p)
    ''');
    final r = rows.first;
    return StockSummary(
      total: (r['total'] as int?) ?? 0,
      low: (r['low'] as int?) ?? 0,
      out: (r['out'] as int?) ?? 0,
    );
  }

  /// Produk yang stoknya <= minimum, yang paling sedikit lebih dulu.
  Future<List<ProductModel>> getLowStockProducts({int limit = 5}) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT * FROM (SELECT $_productColumns FROM products p) '
      'WHERE stock <= min_stock '
      'ORDER BY stock ASC, name COLLATE NOCASE ASC LIMIT ?',
      [limit],
    );
    return rows.map(ProductModel.fromDb).toList();
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT category FROM products ORDER BY category COLLATE NOCASE',
    );
    return rows.map((r) => r['category'] as String).toList();
  }

  // ===================================================================
  // Penjualan langsung (ditulis lokal dulu, lalu dikirim ke server)
  // ===================================================================

  Future<void> insertSale(SaleModel sale) async {
    final db = await database;
    await db.insert('sales', sale.toDb());
  }

  Future<List<SaleModel>> getSales({int limit = 50, int offset = 0}) async {
    final db = await database;
    final rows = await db.query(
      'sales',
      orderBy: 'sold_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(SaleModel.fromDb).toList();
  }

  /// Penjualan milik [cashierId] yang belum terkirim dan belum pernah ditolak.
  /// Difilter per kasir karena server memakai akun yang sedang login sebagai
  /// kasir; tanpa filter, penjualan akun lain di perangkat yang sama akan
  /// tercatat atas nama yang salah.
  Future<List<SaleModel>> getPendingSales(String cashierId) async {
    final db = await database;
    final rows = await db.query(
      'sales',
      where: 'synced = 0 AND sync_error IS NULL AND cashier_id = ?',
      whereArgs: [cashierId],
      orderBy: 'sold_at ASC',
    );
    return rows.map(SaleModel.fromDb).toList();
  }

  Future<int> countPendingSales(String cashierId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sales '
      'WHERE synced = 0 AND sync_error IS NULL AND cashier_id = ?',
      [cashierId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Menandai terkirim. [server] (baris sales dari server) bila ada akan
  /// menimpa nama, harga satuan, dan total lokal dengan nilai resmi server.
  Future<void> markSaleSynced(String id, {Map<String, dynamic>? server}) async {
    final db = await database;
    final values = <String, Object?>{'synced': 1, 'sync_error': null};
    if (server != null) {
      final name = server['product_name'];
      final unit = server['unit_price'];
      final total = server['total'];
      if (name is String) values['product_name'] = name;
      if (unit is num) values['unit_price'] = unit.toInt();
      if (total is num) values['total'] = total.toInt();
    }
    await db.update('sales', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markSaleError(String id, String message) async {
    final db = await database;
    await db.update(
      'sales',
      {'sync_error': message},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Jumlah dan total penjualan sejak [isoUtc] (tanpa yang ditolak server).
  Future<({int count, int total})> getSalesSince(String isoUtc) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(total), 0) AS t FROM sales '
      'WHERE sold_at >= ? AND sync_error IS NULL',
      [isoUtc],
    );
    return (
      count: (r.first['c'] as int?) ?? 0,
      total: (r.first['t'] as int?) ?? 0,
    );
  }

  /// Semua penjualan di perangkat yang masih menunggu dikirim (semua kasir).
  Future<int> countAllPendingSales() async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sales WHERE synced = 0 AND sync_error IS NULL',
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> countRejectedSales() async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sales WHERE synced = 0 AND sync_error IS NOT NULL',
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Menyimpan penjualan dari server. Baris dengan id yang sama (mis. penjualan
  /// lokal yang sebenarnya sudah diterima server) ditimpa dan menjadi synced.
  Future<void> upsertServerSales(List<SaleModel> sales) async {
    if (sales.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final s in sales) {
      batch.insert(
        'sales',
        s.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Penjualan ditolak -> dikirim ulang (hapus penanda error).
  Future<void> retrySale(String id) async {
    final db = await database;
    await db.update(
      'sales',
      {'sync_error': null},
      where: 'id = ? AND synced = 0',
      whereArgs: [id],
    );
  }

  /// Hanya menghapus penjualan yang DITOLAK server (belum pernah tercatat di server).
  Future<void> deleteRejectedSale(String id) async {
    final db = await database;
    await db.delete(
      'sales',
      where: 'id = ? AND synced = 0 AND sync_error IS NOT NULL',
      whereArgs: [id],
    );
  }

  // ===================================================================
  // Penanda notifikasi
  // ===================================================================

  /// Produk yang stok menipisnya sudah pernah diberitahukan.
  Future<Set<String>> getAlertedProductIds() async {
    final db = await database;
    final rows = await db.query('low_stock_alerts', columns: ['product_id']);
    return rows.map((r) => r['product_id'] as String).toSet();
  }

  Future<void> markProductsAlerted(List<String> productIds) async {
    if (productIds.isEmpty) return;
    final db = await database;
    final now = SaleModel.normalizeIso(DateTime.now());
    final batch = db.batch();
    for (final id in productIds) {
      batch.insert('low_stock_alerts', {
        'product_id': id,
        'notified_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearProductAlert(String productId) async {
    final db = await database;
    await db.delete(
      'low_stock_alerts',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  // ===================================================================
  // sync_meta
  // ===================================================================

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert('sync_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Skema dari sqlite_schema.sql
  static const List<String> _schema = [
    '''
    CREATE TABLE products (
      id          TEXT PRIMARY KEY,
      sku         TEXT NOT NULL,
      name        TEXT NOT NULL,
      category    TEXT NOT NULL,
      description TEXT,
      price       INTEGER NOT NULL,
      stock       INTEGER NOT NULL DEFAULT 0,
      min_stock   INTEGER NOT NULL DEFAULT 5,
      is_active   INTEGER NOT NULL DEFAULT 1,
      updated_at  TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_products_category ON products (category)',
    'CREATE INDEX idx_products_name ON products (name)',
    '''
    CREATE TABLE sales (
      id           TEXT PRIMARY KEY,
      product_id   TEXT NOT NULL,
      product_name TEXT NOT NULL,
      unit_price   INTEGER NOT NULL,
      qty          INTEGER NOT NULL CHECK (qty > 0),
      total        INTEGER NOT NULL,
      cashier_id   TEXT NOT NULL,
      sold_at      TEXT NOT NULL,
      synced       INTEGER NOT NULL DEFAULT 0,
      sync_error   TEXT
    )
    ''',
    'CREATE INDEX idx_sales_sold_at ON sales (sold_at DESC)',
    'CREATE INDEX idx_sales_synced ON sales (synced)',
    '''
    CREATE TABLE exchange_rates (
      base       TEXT NOT NULL,
      target     TEXT NOT NULL,
      rate       REAL NOT NULL,
      fetched_at TEXT NOT NULL,
      PRIMARY KEY (base, target)
    )
    ''',
    '''
    CREATE TABLE low_stock_alerts (
      product_id  TEXT PRIMARY KEY,
      notified_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE sync_meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ];
}
