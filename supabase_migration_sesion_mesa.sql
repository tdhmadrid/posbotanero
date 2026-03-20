-- ============================================================
-- RestaurantePOS — Migración: apertura de mesa por mesero
-- ⚠️  Si ya ejecutaste este script y solo falló la línea
--     ALTER PUBLICATION, los campos ya están creados correctamente.
-- ============================================================

-- 1. Añadir campos de sesión a pos_mesas (IF NOT EXISTS = seguro re-ejecutar)
ALTER TABLE pos_mesas
  ADD COLUMN IF NOT EXISTS sesion_activa  boolean     DEFAULT false,
  ADD COLUMN IF NOT EXISTS comensales     integer     DEFAULT 0,
  ADD COLUMN IF NOT EXISTS abierta_por    text        REFERENCES pos_users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS abierta_at     timestamptz DEFAULT NULL;

-- 2. Actualizar constraint de estado en pos_pedidos
ALTER TABLE pos_pedidos
  DROP CONSTRAINT IF EXISTS pos_pedidos_estado_check;

ALTER TABLE pos_pedidos
  ADD CONSTRAINT pos_pedidos_estado_check
  CHECK (estado IN ('abierto','en-cocina','listo','entregado','pagado','cancelado'));

-- 3. Verificar columnas añadidas
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'pos_mesas'
  AND column_name IN ('sesion_activa','comensales','abierta_por','abierta_at')
ORDER BY column_name;
