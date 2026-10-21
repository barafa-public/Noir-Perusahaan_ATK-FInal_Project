insert into users (username, password_hash, full_name, role)
values (
  'admin',
  extensions.crypt('GANTI_PASSWORD_INI', extensions.gen_salt('bf', 10)),
  'Pemilik Toko',
  'internal'
);

-- Produk ATK awal (stok sengaja ada yang dekat batas minimum untuk uji notifikasi).
insert into products (sku, name, category, description, price, stock, min_stock) values
  ('ATK-001', 'Pulpen Hitam',            'Alat Tulis',        'Pulpen tinta hitam 0,5 mm',        3500,  60, 10),
  ('ATK-002', 'Pulpen Biru',             'Alat Tulis',        'Pulpen tinta biru 0,5 mm',         3500,  48, 10),
  ('ATK-003', 'Pensil 2B',               'Alat Tulis',        'Pensil kayu 2B',                   2500,  40, 10),
  ('ATK-004', 'Penghapus',               'Alat Tulis',        'Penghapus putih sedang',           2000,  30,  8),
  ('ATK-005', 'Spidol Whiteboard',       'Alat Tulis',        'Spidol whiteboard hitam',          9000,  12,  5),
  ('ATK-006', 'Buku Tulis 38 Lembar',    'Kertas',            'Buku tulis bergaris 38 lembar',    4500,  80, 15),
  ('ATK-007', 'Kertas A4 70 gr (rim)',   'Kertas',            'Kertas HVS A4 70 gr isi 500',     52000,  25,  5),
  ('ATK-008', 'Map Plastik',             'Map & Arsip',       'Map plastik snap folio',           3000,  35, 10),
  ('ATK-009', 'Stapler Kecil',           'Perlengkapan Meja', 'Stapler mini dengan isi',         12000,  10,  3),
  ('ATK-010', 'Isi Staples No. 10',      'Perlengkapan Meja', 'Isi staples No. 10 (1 kotak)',     3000,   6,  5);
