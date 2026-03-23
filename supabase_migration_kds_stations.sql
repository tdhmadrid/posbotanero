-- ============================================================
-- RestaurantePOS — Migración: KDS por cocinas / estaciones
-- Ejecutar en: Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1. Tabla de estaciones KDS (cocina caliente, barra, paso, etc.)
CREATE TABLE IF NOT EXISTS pos_kds_stations (
  id          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  nombre      text NOT NULL,
  emoji       text DEFAULT '🍳',
  color       text DEFAULT '#f59e0b',
  activa      boolean DEFAULT true,
  orden       integer DEFAULT 0,
  created_at  timestamptz DEFAULT now()
);

-- 2. Añadir kds_ids[] a pos_carta (array de estaciones destino)
ALTER TABLE pos_carta
  ADD COLUMN IF NOT EXISTS kds_ids   text[]  DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS impresoras text[] DEFAULT '{}';

-- 3. Estaciones de ejemplo
INSERT INTO pos_kds_stations (id, nombre, emoji, color, orden) VALUES
  ('kds-cocina',  'Cocina caliente', '🔥', '#ef4444', 1),
  ('kds-fria',    'Cocina fría',     '🥗', '#22c55e', 2),
  ('kds-barra',   'Barra / Bebidas', '🍹', '#3b82f6', 3),
  ('kds-paso',    'Paso',            '🛎️', '#f59e0b', 4)
ON CONFLICT (id) DO NOTHING;

-- 4. Activar Realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'pos_kds_stations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pos_kds_stations;
  END IF;
END $$;

-- 5. Verificar
SELECT id, nombre, emoji, color FROM pos_kds_stations ORDER BY orden;
SELECT column_name FROM information_schema.columns
WHERE table_name = 'pos_carta' AND column_name IN ('kds_ids','impresoras');
