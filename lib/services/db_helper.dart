import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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