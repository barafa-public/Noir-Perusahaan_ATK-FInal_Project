-- =====================================================================
-- Noir - Pencatatan blockchain untuk penjualan (PBI-14).
-- Jalankan SEKALI di SQL Editor Supabase, setelah schema.sql dan seed.sql.
-- Aman dijalankan ulang.
-- =====================================================================

-- Satu penjualan hanya boleh punya satu blok.
create unique index if not exists blocks_sale_ref_key
  on blocks (ref_id) where block_type = 'SALE';

-- Menambahkan blok untuk satu penjualan. Idempoten: jika blok sudah ada,
-- dikembalikan apa adanya. Kunci advisory membuat penambahan blok berurutan
-- walau ada beberapa penjualan yang masuk bersamaan.
--   hash = SHA-256( block_index | block_type | ref_id | payload | prev_hash )
create or replace function append_sale_block(p_sale_id uuid)
returns blocks
language plpgsql as $$
declare
  v_sale    sales;
  v_last    blocks;
  v_block   blocks;
  v_index   bigint;
  v_payload text;
  v_hash    text;
begin
  perform pg_advisory_xact_lock(7001);

  select * into v_block
  from blocks where block_type = 'SALE' and ref_id = p_sale_id;
  if found then return v_block; end if;

  select * into v_sale from sales where id = p_sale_id;
  if not found then raise exception 'SALE_NOT_FOUND'; end if;

  select * into v_last from blocks order by block_index desc limit 1;
  if not found then raise exception 'CHAIN_NOT_INITIALIZED'; end if;

  v_index := v_last.block_index + 1;
  v_payload :=
    'product=' || v_sale.product_name ||
    ';qty='        || v_sale.qty::text ||
    ';unit_price=' || v_sale.unit_price::text ||
    ';total='      || v_sale.total::text ||
    ';sold_at='    || to_char(v_sale.sold_at at time zone 'UTC',
                              'YYYY-MM-DD"T"HH24:MI:SS"Z"') ||
    ';cashier='    || v_sale.cashier_id::text;

  v_hash := encode(
    extensions.digest(
      v_index::text || '|SALE|' || p_sale_id::text || '|' ||
      v_payload || '|' || v_last.hash,
      'sha256'),
    'hex');

  insert into blocks (block_index, block_type, ref_id, payload, prev_hash, hash)
  values (v_index, 'SALE', p_sale_id, v_payload, v_last.hash, v_hash)
  returning * into v_block;

  return v_block;
end $$;

-- record_sale yang sama seperti sebelumnya, ditambah pencatatan blok di
-- transaksi yang sama: penjualan dan bloknya berhasil atau gagal bersama.
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

  perform append_sale_block(v_sale.id);
  return v_sale;
end $$;

-- Hanya service role (Edge Function) yang boleh menjalankannya.
revoke execute on function append_sale_block(uuid) from public, anon, authenticated;
grant  execute on function append_sale_block(uuid) to service_role;

-- Penjualan yang sudah ada sebelum migrasi ini diberi blok (urut waktu diterima).
do $$
declare s record;
begin
  for s in
    select sl.id from sales sl
    where not exists (
      select 1 from blocks b where b.block_type = 'SALE' and b.ref_id = sl.id
    )
    order by sl.created_at, sl.id
  loop
    perform append_sale_block(s.id);
  end loop;
end $$;
