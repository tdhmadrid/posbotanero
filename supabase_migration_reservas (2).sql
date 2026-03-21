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

-- 3. Activar Realtime (ignorar si ya está añadida)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'pos_reservas'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pos_reservas;
  END IF;
END $$;

-- 4. Email del restaurante en config (para notificaciones)
ALTER TABLE pos_config
  ADD COLUMN IF NOT EXISTS email text DEFAULT '';

-- 5. Verificar
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'pos_reservas'
ORDER BY ordinal_position;

-- 6. Campos de configuración de reservas en pos_config
ALTER TABLE pos_config
  ADD COLUMN IF NOT EXISTS res_activo         boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS res_hora_desde     time    DEFAULT '12:00',
  ADD COLUMN IF NOT EXISTS res_hora_hasta     time    DEFAULT '23:00',
  ADD COLUMN IF NOT EXISTS res_intervalo_min  integer DEFAULT 30,
  ADD COLUMN IF NOT EXISTS res_antelacion_min integer DEFAULT 60,
  ADD COLUMN IF NOT EXISTS res_antelacion_max integer DEFAULT 30,
  ADD COLUMN IF NOT EXISTS res_pax_max        integer DEFAULT 20,
  ADD COLUMN IF NOT EXISTS res_campo_email    text    DEFAULT 'opcional'
    CHECK (res_campo_email    IN ('oculto','opcional','obligatorio')),
  ADD COLUMN IF NOT EXISTS res_campo_nota     text    DEFAULT 'opcional'
    CHECK (res_campo_nota     IN ('oculto','opcional','obligatorio')),
  ADD COLUMN IF NOT EXISTS res_campo_zona     text    DEFAULT 'opcional'
    CHECK (res_campo_zona     IN ('oculto','opcional','obligatorio')),
  ADD COLUMN IF NOT EXISTS res_msg_confirmacion text  DEFAULT '¡Gracias por tu reserva! Te esperamos.',
  ADD COLUMN IF NOT EXISTS res_politica       text    DEFAULT '';
