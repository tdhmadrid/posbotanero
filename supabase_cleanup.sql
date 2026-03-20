-- ============================================================
-- RestaurantePOS — Script de limpieza de datos de seed
-- Ejecutar en: Supabase → SQL Editor → New query → Run
-- 
-- Esto borra los datos insertados por el script de setup inicial
-- y deja solo los datos creados desde el Admin.
-- Ejecutar SOLO si tienes datos duplicados o mesas que no aparecen.
-- ============================================================

-- 1. Borrar mesas y zonas del seed (IDs fijos del setup.sql)
delete from pos_mesas where id in (
  'm-1','m-2','m-3','m-4','m-5','m-6','m-7','m-8','m-9'
);

delete from pos_zonas where id in (
  'z-interior','z-terraza','z-barra','z-vip'
);

-- 2. Borrar productos y categorías del seed
delete from pos_carta where id in (
  'c-1','c-2','c-3','c-4','c-5','c-6','c-7','c-8','c-9','c-10',
  'c-11','c-12','c-13','c-14','c-15','c-16','c-17','c-18','c-19',
  'c-20','c-21','c-22','c-23','c-24','c-25'
);

delete from pos_cats where id in (
  'ct-menu','ct-entrantes','ct-principales','ct-postres','ct-bebidas'
);

-- 3. Verificar qué queda
select 'pos_zonas' as tabla, count(*) as filas from pos_zonas
union all
select 'pos_mesas', count(*) from pos_mesas
union all
select 'pos_cats', count(*) from pos_cats
union all
select 'pos_carta', count(*) from pos_carta
union all
select 'pos_users', count(*) from pos_users;
