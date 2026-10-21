create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Tabel
-- ---------------------------------------------------------------------

create table users (
  id            uuid primary key default gen_random_uuid(),
  username      text not null,
  password_hash text not null,                       -- bcrypt (salt sudah di dalam hash)
  full_name     text not null,
  role          text not null default 'internal'
                check (role in ('internal')),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
create unique index users_username_key on users (lower(username));

create table products (
  id          uuid primary key default gen_random_uuid(),
  sku         text not null unique,
  name        text not null,
  category    text not null,
  description text,
  price       bigint  not null check (price >= 0),   -- rupiah
  stock       integer not null default 0 check (stock >= 0),
  min_stock   integer not null default 5 check (min_stock >= 0),
  is_active   boolean not null default true,         -- "hapus" = nonaktifkan, agar cache klien ikut terhapus
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index products_category_idx   on products (category);
create index products_updated_at_idx on products (updated_at);

-- Penjualan di toko (satu baris = satu produk).
-- id dibuat di perangkat (UUID) agar pengiriman ulang tidak menggandakan data.
create table sales (
  id           uuid primary key,
  product_id   uuid not null references products (id),
  product_name text   not null,
  unit_price   bigint not null check (unit_price >= 0),
  qty          integer not null check (qty > 0),
  total        bigint not null check (total >= 0),
  cashier_id   uuid not null references users (id),
  sold_at      timestamptz not null,                 -- waktu transaksi di perangkat
  created_at   timestamptz not null default now()    -- waktu diterima server
);
create index sales_sold_at_idx on sales (sold_at desc);
create index sales_product_idx on sales (product_id);

-- Blockchain sederhana: satu rantai untuk semua perangkat.
-- hash = SHA-256 dari: block_index|block_type|ref_id|payload|prev_hash
-- (ref_id kosong untuk blok genesis). payload disimpan sebagai teks persis
-- yang di-hash, supaya verifikasi tidak bergantung pada format JSON.
create table blocks (
  block_index bigint primary key,
  block_type  text not null check (block_type in ('GENESIS', 'SALE')),
  ref_id      uuid,                                  -- id penjualan
  payload     text not null,
  prev_hash   text not null,
  hash        text not null unique,
  created_at  timestamptz not null default now()
);

create table feedback (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users (id),
  impression text not null,                          -- kesan
  suggestion text not null,                          -- saran
  rating     smallint not null check (rating between 1 and 5),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. Trigger updated_at (dipakai sinkronisasi produk "sejak waktu X")
-- ---------------------------------------------------------------------

create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger products_set_updated_at before update on products
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------
-- 3. Fungsi atomik (dipanggil Edge Function lewat rpc)
--    Pesan kesalahan memakai kode: INSUFFICIENT_STOCK: <nama produk>,
--    PRODUCT_NOT_FOUND, INVALID_QTY
-- ---------------------------------------------------------------------

-- Penjualan dari perangkat. Aman dikirim ulang: id yang sudah ada
-- dikembalikan apa adanya tanpa mengurangi stok dua kali.
create or replace function record_sale(
  p_id uuid, p_product_id uuid, p_qty integer, p_cashier_id uuid, p_sold_at timestamptz
) returns sales
language plpgsql as $$
declare
  v_prod products;
  v_sale sales;
begin
  select * into v_sale from sales where id = p_id;
  if found then return v_sale; end if;

  if p_qty is null or p_qty <= 0 then raise exception 'INVALID_QTY'; end if;

  select * into v_prod from products where id = p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  if v_prod.stock < p_qty then
    raise exception 'INSUFFICIENT_STOCK: %', v_prod.name;
  end if;

  update products set stock = stock - p_qty where id = p_product_id;

  insert into sales (id, product_id, product_name, unit_price, qty, total, cashier_id, sold_at)
  values (p_id, v_prod.id, v_prod.name, v_prod.price, p_qty, v_prod.price * p_qty,
          p_cashier_id, p_sold_at)
  returning * into v_sale;
  return v_sale;
end $$;

-- ---------------------------------------------------------------------
-- 4. Kunci akses: RLS aktif tanpa policy + cabut hak anon/authenticated.
--    Hanya service role (Edge Function) yang dapat mengakses data.
-- ---------------------------------------------------------------------

alter table users       enable row level security;
alter table products    enable row level security;
alter table sales       enable row level security;
alter table blocks      enable row level security;
alter table feedback    enable row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;

-- Fungsi secara bawaan bisa dijalankan siapa saja, jadi dicabut eksplisit.
revoke execute on function
  record_sale(uuid, uuid, integer, uuid, timestamptz)
from public, anon, authenticated;

grant execute on function
  record_sale(uuid, uuid, integer, uuid, timestamptz)
to service_role;

-- ---------------------------------------------------------------------
-- 5. Blok genesis (index 0). Rumus hash harus sama dengan blockchain_service
--    dan Edge Function blocks: index|type|ref_id|payload|prev_hash
-- ---------------------------------------------------------------------

insert into blocks (block_index, block_type, ref_id, payload, prev_hash, hash)
values (
  0, 'GENESIS', null, 'Noir Genesis', repeat('0', 64),
  encode(
    extensions.digest('0|GENESIS||Noir Genesis|' || repeat('0', 64), 'sha256'),
    'hex')
);
