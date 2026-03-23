-- ============================================================
-- RestaurantePOS — Migración: EmailJS + Multi-tenant + Recordatorios
-- Ejecutar en: Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1. Campos EmailJS y multi-tenant en pos_config
ALTER TABLE pos_config
  -- Multi-tenant: slug único por restaurante (usado en ?id=slug)
  ADD COLUMN IF NOT EXISTS slug              text UNIQUE DEFAULT NULL,
  -- EmailJS credentials
  ADD COLUMN IF NOT EXISTS ejs_service_id   text DEFAULT '',
  ADD COLUMN IF NOT EXISTS ejs_public_key   text DEFAULT '',
  -- Templates IDs
  ADD COLUMN IF NOT EXISTS ejs_tpl_restaurante  text DEFAULT '',  -- nueva reserva → restaurante
  ADD COLUMN IF NOT EXISTS ejs_tpl_cliente      text DEFAULT '',  -- confirmación → cliente
  ADD COLUMN IF NOT EXISTS ejs_tpl_cancelacion  text DEFAULT '',  -- cancelación → restaurante
  ADD COLUMN IF NOT EXISTS ejs_tpl_recordatorio text DEFAULT '',  -- recordatorio 24h → cliente
  -- Email destino del restaurante (para notificaciones)
  ADD COLUMN IF NOT EXISTS email_notif      text DEFAULT '';

-- 2. Control de recordatorios en pos_reservas
ALTER TABLE pos_reservas
  ADD COLUMN IF NOT EXISTS recordatorio_enviado boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS confirmacion_enviada boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS cancelacion_enviada  boolean DEFAULT false;

-- 3. Crear índice para búsqueda por slug
CREATE INDEX IF NOT EXISTS idx_config_slug ON pos_config(slug);

-- 4. Función para buscar config pública por slug (sin exponer datos sensibles)
-- Usada desde pos_reservas.html?id=slug sin autenticación
CREATE OR REPLACE FUNCTION get_config_by_slug(p_slug text)
RETURNS TABLE (
  id           integer,
  nombre       text,
  slug         text,
  dir          text,
  tel          text,
  res_activo   boolean,
  res_horario  jsonb,
  res_intervalo_min integer,
  res_antelacion_min integer,
  res_antelacion_max integer,
  res_pax_max  integer,
  res_campo_email text,
  res_campo_nota  text,
  res_campo_zona  text,
  res_msg_confirmacion text,
  res_politica text,
  ejs_service_id    text,
  ejs_public_key    text,
  ejs_tpl_restaurante  text,
  ejs_tpl_cliente      text,
  ejs_tpl_recordatorio text,
  email_notif  text
) LANGUAGE sql STABLE AS $$
  SELECT
    id, nombre, slug, dir, tel,
    res_activo, res_horario, res_intervalo_min,
    res_antelacion_min, res_antelacion_max, res_pax_max,
    res_campo_email, res_campo_nota, res_campo_zona,
    res_msg_confirmacion, res_politica,
    ejs_service_id, ejs_public_key,
    ejs_tpl_restaurante, ejs_tpl_cliente, ejs_tpl_recordatorio,
    email_notif
  FROM pos_config
  WHERE slug = p_slug
  LIMIT 1;
$$;

-- 5. Función para recordatorios pendientes (llamada por cron o manualmente)
-- Devuelve reservas de mañana que no han recibido recordatorio
CREATE OR REPLACE FUNCTION get_pending_reminders()
RETURNS TABLE (
  reserva_id  text,
  nombre      text,
  email       text,
  fecha       date,
  hora        time,
  personas    integer,
  nota        text,
  rest_nombre text,
  rest_dir    text,
  rest_tel    text
) LANGUAGE sql STABLE AS $$
  SELECT
    r.id, r.nombre, r.email, r.fecha, r.hora, r.personas, r.nota,
    c.nombre, c.dir, c.tel
  FROM pos_reservas r
  CROSS JOIN pos_config c
  WHERE c.id = 1
    AND r.fecha = CURRENT_DATE + INTERVAL '1 day'
    AND r.estado IN ('pendiente', 'confirmada')
    AND r.email IS NOT NULL AND r.email != ''
    AND r.recordatorio_enviado = false;
$$;

-- 6. Actualizar slug por defecto al restaurante existente (id=1)
-- Genera un slug a partir del nombre si existe
UPDATE pos_config
SET slug = LOWER(REGEXP_REPLACE(COALESCE(nombre, 'mi-restaurante'), '[^a-zA-Z0-9]', '-', 'g'))
WHERE id = 1 AND slug IS NULL;

-- Verificar
SELECT id, nombre, slug, ejs_service_id, email_notif FROM pos_config WHERE id = 1;
