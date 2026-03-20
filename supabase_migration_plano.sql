-- ============================================================
-- RestaurantePOS — Migración: plano de mesas interactivo
-- Ejecutar en: Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1. Añadir coordenadas de posición a pos_mesas
ALTER TABLE pos_mesas
  ADD COLUMN IF NOT EXISTS pos_x    integer DEFAULT 100,
  ADD COLUMN IF NOT EXISTS pos_y    integer DEFAULT 100,
  ADD COLUMN IF NOT EXISTS forma    text    DEFAULT 'cuadrada'
    CHECK (forma IN ('cuadrada','redonda','rectangular'));

-- 2. Tabla de elementos del plano (mobiliario, divisiones, etc.)
CREATE TABLE IF NOT EXISTS pos_plano_items (
  id         text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tipo       text NOT NULL
    CHECK (tipo IN ('pared','barra','ventana','puerta','planta','banos','mostrador','zona')),
  label      text DEFAULT '',
  pos_x      integer NOT NULL DEFAULT 50,
  pos_y      integer NOT NULL DEFAULT 50,
  ancho      integer NOT NULL DEFAULT 120,
  alto       integer NOT NULL DEFAULT 40,
  color      text DEFAULT '#333',
  created_at timestamptz DEFAULT now()
);

-- Activar Realtime para el plano
ALTER PUBLICATION supabase_realtime ADD TABLE pos_plano_items;

-- 3. Verificar
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'pos_mesas'
  AND column_name IN ('pos_x','pos_y','forma')
ORDER BY column_name;
