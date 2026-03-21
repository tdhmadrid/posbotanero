-- ============================================================
-- RestaurantePOS — Migración: Reservaciones y Valoraciones
-- Ejecutar en: Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1. Tabla de reservaciones
CREATE TABLE IF NOT EXISTS pos_reservas (
  id            text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  fecha         date NOT NULL,
  hora          time NOT NULL,
  nombre        text NOT NULL,
  telefono      text DEFAULT '',
  email         text DEFAULT '',
  personas      integer NOT NULL DEFAULT 2,
  mesa_id       text REFERENCES pos_mesas(id) ON DELETE SET NULL,
  nota          text DEFAULT '',
  origen        text DEFAULT 'telefono'
    CHECK (origen IN ('telefono','web','en_persona','otro')),
  estado        text DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente','confirmada','cancelada','completada','no_show')),
  -- Calificación del restaurante al cliente (1-5)
  rating_cliente     integer CHECK (rating_cliente BETWEEN 1 AND 5),
  nota_interna       text DEFAULT '',
  -- Valoración del cliente al restaurante
  rating_restaurante integer CHECK (rating_restaurante BETWEEN 1 AND 5),
  comentario_cliente text DEFAULT '',
  valoracion_at      timestamptz,
  -- Token único para que el cliente acceda a valorar sin login
  token_valoracion   text DEFAULT gen_random_uuid()::text,
  user_id       text REFERENCES pos_users(id) ON DELETE SET NULL,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

-- 2. Índices útiles
CREATE INDEX IF NOT EXISTS idx_reservas_fecha   ON pos_reservas(fecha);
CREATE INDEX IF NOT EXISTS idx_reservas_estado  ON pos_reservas(estado);
CREATE INDEX IF NOT EXISTS idx_reservas_token   ON pos_reservas(token_valoracion);

-- 3. Activar Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE pos_reservas;

-- 4. Email del restaurante en config (para notificaciones)
ALTER TABLE pos_config
  ADD COLUMN IF NOT EXISTS email text DEFAULT '';

-- 5. Verificar
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'pos_reservas'
ORDER BY ordinal_position;
