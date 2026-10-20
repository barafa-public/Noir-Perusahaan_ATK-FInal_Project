import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product_model.dart';
import '../models/sale_model.dart';

class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static const _dbName = 'noir.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        // Satu panggilan execute = satu statement.
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Isi migrasi di sini saat _dbVersion dinaikkan.
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
            'cart_items',
            where: 'product_id = ?',
            whereArgs: [p.id],
          );
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

  /// Daftar produk, opsional dicari (nama/SKU) dan difilter kategori.
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
      where.add(r"(name LIKE ? ESCAPE '\' OR sku LIKE ? ESCAPE '\')");
      args
        ..add('%$esc%')
        ..add('%$esc%');
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }

    final rows = await db.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(ProductModel.fromDb).toList();
  }

  Future<ProductModel?> getProduct(String id) async {
    final db = await database;
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ProductModel.fromDb(rows.first);
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT category FROM products ORDER BY category COLLATE NOCASE',
    );
    return rows.map((r) => r['category'] as String).toList();
  }

  // ===================================================================
  // Keranjang (draft per akun)
  // ===================================================================

  /// product_id -> qty
  Future<Map<String, int>> getCart(String userId) async {
    final db = await database;
    final rows = await db.query(
      'cart_items',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return {for (final r in rows) r['product_id'] as String: r['qty'] as int};
  }

  /// qty <= 0 menghapus item dari keranjang.
  Future<void> setCartQty(String userId, String productId, int qty) async {
    final db = await database;
    if (qty <= 0) {
      await db.delete(
        'cart_items',
        where: 'user_id = ? AND product_id = ?',
        whereArgs: [userId, productId],
      );
      return;
    }
    await db.insert('cart_items', {
      'user_id': userId,
      'product_id': productId,
      'qty': qty,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearCart(String userId) async {
    final db = await database;
    await db.delete('cart_items', where: 'user_id = ?', whereArgs: [userId]);
  }

  // ===================================================================
  // Penjualan langsung (ditulis lokal dulu, lalu dikirim ke server)
  // ===================================================================

  Future<void> insertSale(SaleModel sale) async {
    final db = await database;
    await db.insert('sales', sale.toDb());
  }

  Future<List<SaleModel>> getSales({int? limit}) async {
    final db = await database;
    final rows = await db.query('sales', orderBy: 'sold_at DESC', limit: limit);
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
    CREATE TABLE cart_items (
      user_id    TEXT NOT NULL,
      product_id TEXT NOT NULL,
      qty        INTEGER NOT NULL CHECK (qty > 0),
      PRIMARY KEY (user_id, product_id)
    )
    ''',
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
    CREATE TABLE order_status_cache (
      order_id TEXT PRIMARY KEY,
      order_no TEXT NOT NULL,
      status   TEXT NOT NULL
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
