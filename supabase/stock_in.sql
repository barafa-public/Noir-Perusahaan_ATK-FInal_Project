-- =====================================================================
-- Noir - Penambahan stok atomik ("Tambah stok").
-- Jalankan SEKALI di SQL Editor Supabase. Aman dijalankan ulang.
-- Menjumlahkan stok di database (bukan menimpa), sehingga penjualan yang
-- masuk bersamaan tidak hilang dari hitungan.
-- =====================================================================

create or replace function adjust_stock(p_product_id uuid, p_delta integer)
returns products
language plpgsql
as $$
declare
  v_prod products;
begin
  if p_delta is null or p_delta = 0 or abs(p_delta) > 100000 then
    raise exception 'INVALID_QTY';
  end if;

  update products
     set stock = stock + p_delta
   where id = p_product_id
     and is_active
  returning * into v_prod;

  if not found then
    raise exception 'PRODUCT_NOT_FOUND';
  end if;

  -- Gagal di sini membatalkan seluruh perubahan di atas.
  if v_prod.stock < 0 or v_prod.stock > 1000000 then
    raise exception 'STOCK_OUT_OF_RANGE';
  end if;

  return v_prod;
end;
$$;

revoke execute on function adjust_stock(uuid, integer)
  from public, anon, authenticated;

grant execute on function adjust_stock(uuid, integer)
  to service_role;
