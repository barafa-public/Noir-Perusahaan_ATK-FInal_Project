# Noir

**Aplikasi persediaan dan penjualan alat tulis kantor (ATK) untuk admin toko.**

Noir membantu pemilik toko ATK mencatat produk, stok, dan penjualan langsung dari HP. Aplikasi ini dibuat dengan Flutter sebagai proyek akhir mata kuliah Pemrograman Aplikasi Mobile. Pengguna aplikasi hanya satu peran, yaitu **admin** (pemilik toko), sehingga tidak ada fitur pelanggan seperti keranjang atau pesanan.

Cara kerjanya secara singkat:

- Data utama disimpan di **Supabase** (PostgreSQL) dan diakses lewat Edge Function.
- Data disalin ke **SQLite** di HP, sehingga aplikasi tetap bisa dipakai saat sinyal buruk. Perubahan dikirim ke server saat koneksi kembali.
- Setiap penjualan dicatat sebagai blok di **rantai blockchain sederhana** supaya riwayatnya sulit diubah diam-diam.
- Tersedia alat bantu tambahan: prediksi kebutuhan stok, asisten AI, peta jarak, kurs, zona waktu, dan mini game.

## Daftar Isi

1. [Fitur](#fitur)
2. [Teknologi](#teknologi)
3. [Struktur Folder](#struktur-folder)
4. [Menjalankan Aplikasi](#menjalankan-aplikasi)
5. [Backend (Supabase)](#backend-supabase)
6. [Database Lokal (SQLite)](#database-lokal-sqlite)
7. [API yang Digunakan](#api-yang-digunakan)
8. [Alur Aplikasi](#alur-aplikasi)
9. [Pemetaan Kriteria Tugas](#pemetaan-kriteria-tugas)

---

## Fitur

| Kelompok     | Fitur                             | Keterangan                                                                                                      |
| ------------ | --------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Akun         | Login dan logout                  | Satu akun admin. Kata sandi di-hash dengan bcrypt, sesi memakai JWT.                                            |
| Akun         | Profil dan Pengaturan             | Mengubah mata uang tampilan dan zona waktu tampilan.                                                            |
| Produk       | Daftar, cari, tambah, ubah, hapus | Hapus berarti menonaktifkan produk, supaya cache di HP ikut bersih.                                             |
| Produk       | Tambah stok dengan sensor         | Putar HP (gyroscope) untuk menambah atau mengurangi jumlah, goyang HP (accelerometer) untuk mengulang dari nol. |
| Penjualan    | Input penjualan                   | Stok berkurang otomatis dan waktu transaksi tercatat.                                                           |
| Penjualan    | Riwayat                           | Dikelompokkan per hari, ditampilkan jam input dan rincian transaksi di beberapa zona waktu.                     |
| Stok         | Notifikasi stok menipis           | Pemberitahuan lokal saat stok mencapai batas minimum.                                                           |
| Sinkronisasi | Mode offline                      | Data dibaca dari SQLite, perubahan disinkronkan dua arah saat online.                                           |
| Alat         | Prediksi Stok                     | Peramalan penjualan di HP dan saran jumlah restock.                                                             |
| Alat         | Asisten AI                        | Tanya jawab tentang toko dengan LLM lewat Edge Function.                                                        |
| Alat         | Lokasi dan Jarak                  | Peta OpenStreetMap, titik asal dari GPS, tujuan dipilih di peta atau dicari lewat nama tempat.                  |
| Alat         | Blockchain                        | Melihat rantai blok penjualan dan memverifikasi keutuhannya.                                                    |
| Alat         | Mini Game                         | Tebak Harga ATK dengan skor tertinggi tersimpan di HP.                                                          |
| Umpan balik  | Kesan dan saran                   | Formulir kesan, saran, dan nilai 1 sampai 5.                                                                    |

## Teknologi

| Bagian         | Teknologi                                                     |
| -------------- | ------------------------------------------------------------- |
| Aplikasi       | Flutter (Dart 3, SDK `>=3.3.0 <4.0.0`), Material 3 tema gelap |
| Backend        | Supabase: PostgreSQL dan Edge Function (Deno, TypeScript)     |
| Autentikasi    | Buatan sendiri: bcrypt dan JWT HS256 (bukan Supabase Auth)    |
| Database lokal | SQLite (`sqflite`)                                            |
| Peta           | `flutter_map` dan `latlong2`, tile OpenStreetMap              |
| Sensor         | `sensors_plus` (gyroscope dan accelerometer)                  |
| Lokasi         | GPS perangkat, pencarian tempat dengan Nominatim              |
| AI             | Gemini lewat Edge Function `ai-chat`                          |
| Ikon aplikasi  | `flutter_launcher_icons`                                      |

## Struktur Folder

```text
Noir/
├── assets/images/            Logo dan gambar bawaan
├── lib/
│   ├── main.dart             Titik masuk, memuat layanan awal
│   ├── app.dart              Tema dan pembangunan ulang tampilan saat kurs/zona waktu berubah
│   ├── core/                 Warna, formatter, konstanta, utilitas
│   ├── models/               Model data (produk, penjualan, dll.)
│   ├── services/             Logika: API, SQLite, sinkronisasi, kurs, waktu, lokasi, sensor, prediksi
│   ├── screens/              Halaman: login, beranda, produk, penjualan, profil, settings, tools
│   └── widgets/              Komponen yang dipakai ulang
├── supabase/
│   ├── schema.sql            Tabel, fungsi, dan pengamanan database
│   ├── seed.sql              Data awal: akun admin dan 10 produk ATK
│   └── functions/            Edge Function (products, blocks, ai-chat, dan lainnya)
├── test/                     Pengujian unit
├── .env                      Konfigurasi (tidak boleh di-commit)
└── pubspec.yaml
```

## Menjalankan Aplikasi

**Yang dibutuhkan:** Flutter SDK (Dart 3.3 atau lebih baru), HP Android dengan mode pengembang aktif, dan akun Supabase.

1. **Siapkan backend** terlebih dahulu (lihat bagian [Backend](#backend-supabase)).
2. **Isi file `.env`** di folder utama proyek dengan alamat dan kunci proyek Supabase Anda. Jangan menaruh kunci rahasia di file ini, karena `.env` ikut terbungkus di dalam APK.
3. **Pasang dependensi dan jalankan:**

```powershell
flutter pub get
flutter run
```

4. **Login** dengan akun dari `seed.sql`: username `admin` dan kata sandi yang Anda tulis sendiri di file tersebut.

Perintah yang berguna:

```powershell
flutter analyze               # periksa kode
flutter test                  # jalankan pengujian
dart run flutter_launcher_icons   # buat ulang ikon aplikasi
```

## Backend (Supabase)

Supabase hanya dipakai sebagai penyimpan data. Semua akses lewat Edge Function, sedangkan tabel dikunci dengan RLS tanpa policy sehingga hanya `service_role` yang bisa membaca atau menulis.

**1. Buat database.** Di SQL Editor Supabase, jalankan berurutan:

| Urutan | File                  | Isi                                                                                       |
| ------ | --------------------- | ----------------------------------------------------------------------------------------- |
| 1      | `supabase/schema.sql` | Tabel `users`, `products`, `sales`, `blocks`, `feedback`, fungsi atomik, dan blok genesis |
| 2      | `supabase/seed.sql`   | Akun admin dan produk awal (ganti `GANTI_PASSWORD_INI` dulu)                              |

**2. Atur rahasia (secret)** untuk Edge Function, misalnya kunci JWT dan `LLM_API_KEY`:

```powershell
npx supabase secrets set LLM_API_KEY=isi_kunci_anda --project-ref <project-ref>
```

**3. Deploy Edge Function.** Setiap fungsi dipasang tanpa verifikasi JWT bawaan Supabase, karena aplikasi memakai JWT buatan sendiri:

```powershell
npx supabase functions deploy products --no-verify-jwt --project-ref <project-ref>
npx supabase functions deploy blocks   --no-verify-jwt --project-ref <project-ref>
npx supabase functions deploy ai-chat  --no-verify-jwt --project-ref <project-ref>
```

Ulangi untuk fungsi lain di `supabase/functions/`. **Deploy ulang setiap kali isi `index.ts` berubah.** Fungsi yang dipasang saat filenya masih kosong akan menggantung tanpa jawaban.

**Fungsi database penting** (di `schema.sql`):

| Fungsi              | Tugas                                                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| `record_sale`       | Mencatat penjualan, mengurangi stok, dan menambah blok dalam satu transaksi. Aman dikirim ulang. |
| `append_sale_block` | Menambah blok ke rantai secara berurutan (dengan kunci advisory).                                |
| `adjust_stock`      | Menambah atau mengurangi stok secara atomik, batas 0 sampai 1.000.000.                           |

## Database Lokal (SQLite)

SQLite di HP berfungsi sebagai cache dan antrean sinkronisasi. Skema versi 2 memiliki lima tabel:

| Tabel              | Fungsi                                    |
| ------------------ | ----------------------------------------- |
| `products`         | Salinan produk dari server                |
| `sales`            | Penjualan, termasuk yang belum terkirim   |
| `exchange_rates`   | Kurs terakhir untuk tampilan mata uang    |
| `low_stock_alerts` | Mencegah notifikasi stok menipis berulang |
| `sync_meta`        | Waktu sinkronisasi terakhir               |

Prinsip data: harga disimpan dalam **Rupiah** dan waktu dalam **UTC**. Mata uang dan zona waktu hanya mengubah tampilan, bukan data.

## API yang Digunakan

**API milik proyek (Supabase Edge Function)**

| Fungsi      | Kegunaan                                                                              |
| ----------- | ------------------------------------------------------------------------------------- |
| Autentikasi | Login admin dan penerbitan JWT                                                        |
| `products`  | Daftar, tambah, ubah, hapus produk, dan `POST /products/<id>/stock` untuk tambah stok |
| Penjualan   | Mengirim dan membaca penjualan                                                        |
| `blocks`    | Membaca rantai blok dan memverifikasinya                                              |
| `ai-chat`   | Meneruskan percakapan ke LLM tanpa membuka kunci API di aplikasi                      |
| Umpan balik | Menyimpan kesan dan saran                                                             |

**API pihak ketiga**

| Layanan              | Kegunaan                                                                    |
| -------------------- | --------------------------------------------------------------------------- |
| OpenStreetMap (tile) | Gambar peta pada halaman Lokasi                                             |
| Nominatim            | Mencari tempat berdasarkan nama dan mengubah titik peta menjadi nama tempat |
| API kurs mata uang   | Mengambil kurs untuk mengubah tampilan harga                                |
| Gemini (Google)      | Model bahasa untuk Asisten AI, diakses lewat `ai-chat`                      |

## Alur Aplikasi

```text
Buka aplikasi
   │
   ├─ belum login ──► Login ──► server memeriksa bcrypt ──► JWT disimpan di HP
   │
   └─ sudah login ──► Beranda
                        │
        ┌───────────────┼─────────────────┬──────────────────┐
        ▼               ▼                 ▼                  ▼
     Produk         Penjualan          Alat bantu          Profil
  (lihat, ubah,   (input, riwayat)   (prediksi, AI,    (pengaturan,
   tambah stok)                       peta, blockchain,  umpan balik,
                                      game)              logout)
```

Alur satu penjualan:

1. Admin memilih produk dan jumlah di halaman Penjualan.
2. Penjualan disimpan ke SQLite dengan ID UUID dari HP.
3. Saat online, `SyncService` mengirimnya ke server. Fungsi `record_sale` mengurangi stok dan menambah blok baru dalam satu transaksi.
4. Jika pengiriman diulang, ID yang sama tidak membuat data ganda.
5. Stok terbaru diunduh, dan notifikasi muncul bila stok di bawah batas minimum.
6. Halaman Blockchain dapat memverifikasi bahwa rantai blok tidak berubah.

## Pemetaan Kriteria Tugas

Ringkasan hubungan antara kriteria proyek akhir dan bagian aplikasi. Sesuaikan nama kriteria dengan dokumen ketentuan dari dosen.

| Kriteria             | Wujud di Noir                                 | Lokasi utama                                                   |
| -------------------- | --------------------------------------------- | -------------------------------------------------------------- |
| Autentikasi dan sesi | Login admin, JWT, logout                      | `screens/auth`, fungsi Edge autentikasi                        |
| CRUD data            | Produk dan penjualan                          | `screens/products`, `screens/sales`                            |
| Database lokal       | SQLite dan sinkronisasi                       | `services/db_helper.dart`, `SyncService`                       |
| Konsumsi API         | Edge Function dan API pihak ketiga            | `services/`                                                    |
| Notifikasi           | Peringatan stok menipis                       | `services/` notifikasi                                         |
| Sensor               | Gyroscope dan accelerometer untuk tambah stok | `services/sensor_service.dart`, `widgets/add_stock_sheet.dart` |
| Lokasi               | Peta, GPS, jarak ke tujuan                    | `screens/tools/location_screen.dart`                           |
| Konversi kurs        | Mata uang tampilan global                     | `services/money_service.dart`                                  |
| Konversi waktu       | Zona waktu tampilan dan jam input             | `services/time_service.dart`                                   |
| Blockchain           | Rantai blok penjualan                         | `supabase/schema.sql`, fungsi `blocks`                         |
| Kecerdasan buatan    | Prediksi stok dan Asisten AI                  | `services/forecast_service.dart`, fungsi `ai-chat`             |
| Mini game            | Tebak Harga ATK                               | `screens/tools/game_screen.dart`                               |
| Kesan dan saran      | Formulir umpan balik                          | Halaman Profil                                                 |
| Laporan              | Dokumen laporan proyek (disusun terpisah)     | Di luar repositori                                             |

---

Proyek ini dibuat untuk keperluan pembelajaran.
