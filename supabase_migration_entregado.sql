-- ============================================================
-- RestaurantePOS — Migración: añadir estado 'entregado'
-- Ejecutar en: Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1. Eliminar el constraint de CHECK actual en estado
ALTER TABLE pos_pedidos
  DROP CONSTRAINT IF EXISTS pos_pedidos_estado_check;

-- 2. Añadir el constraint con el nuevo estado 'entregado'
ALTER TABLE pos_pedidos
  ADD CONSTRAINT pos_pedidos_estado_check
  CHECK (estado IN ('abierto', 'en-cocina', 'listo', 'entregado', 'pagado', 'cancelado'));

-- 3. Verificar (compatible con PostgreSQL 14+)
SELECT conname, pg_get_constraintdef(oid) as definition
FROM pg_constraint
WHERE conrelid = 'pos_pedidos'::regclass
  AND contype = 'c';
