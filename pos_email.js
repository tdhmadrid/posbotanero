/**
 * RestaurantePOS — Email Notifications via EmailJS
 * ==================================================
 * Envía emails de reserva usando EmailJS (sin backend).
 * Se incluye inline en pos_reservas.html y pos_admin.html.
 *
 * Setup:
 *  1. Crear cuenta gratis en https://www.emailjs.com
 *  2. Conectar un servicio de email (Gmail, Outlook, SMTP propio)
 *  3. Crear las plantillas (ver PLANTILLAS más abajo)
 *  4. Copiar Service ID, Public Key y Template IDs a la config del admin
 *
 * PLANTILLAS recomendadas en EmailJS:
 * ─────────────────────────────────────
 * TPL: tpl_nueva_reserva (al restaurante)
 *   Variables: {{rest_nombre}}, {{nombre}}, {{fecha}}, {{hora}},
 *              {{personas}}, {{telefono}}, {{email_cliente}}, {{nota}},
 *              {{origen}}, {{ref}}
 *
 * TPL: tpl_confirmacion_cliente (al cliente)
 *   Variables: {{rest_nombre}}, {{rest_dir}}, {{rest_tel}},
 *              {{nombre}}, {{fecha}}, {{hora}}, {{personas}},
 *              {{nota}}, {{ref}}, {{msg_confirmacion}}
 *
 * TPL: tpl_cancelacion (al restaurante)
 *   Variables: {{rest_nombre}}, {{nombre}}, {{fecha}}, {{hora}},
 *              {{personas}}, {{ref}}
 *
 * TPL: tpl_recordatorio (al cliente, 24h antes)
 *   Variables: {{rest_nombre}}, {{rest_dir}}, {{rest_tel}},
 *              {{nombre}}, {{fecha}}, {{hora}}, {{personas}}, {{ref}}
 */

'use strict';

const PosEmail = (() => {

  let _cfg = null; // { ejs_service_id, ejs_public_key, ejs_tpl_*, email_notif, nombre, ... }

  // ── Inicializar EmailJS con la config del restaurante ──
  function init(cfg) {
    _cfg = cfg;
    if (cfg.ejs_public_key && window.emailjs) {
      emailjs.init({ publicKey: cfg.ejs_public_key });
    }
  }

  // ── ¿Está configurado EmailJS? ──
  function isReady() {
    return !!(
      _cfg &&
      _cfg.ejs_service_id &&
      _cfg.ejs_public_key &&
      window.emailjs
    );
  }

  // ── Enviar email genérico ──
  async function send(templateId, params) {
    if (!isReady()) {
      console.warn('[PosEmail] EmailJS no configurado, saltando email');
      return { ok: false, reason: 'not_configured' };
    }
    if (!templateId) {
      return { ok: false, reason: 'no_template' };
    }
    try {
      await emailjs.send(_cfg.ejs_service_id, templateId, params);
      return { ok: true };
    } catch (e) {
      console.error('[PosEmail] Error enviando email:', e);
      return { ok: false, error: e.text || e.message || e };
    }
  }

  // ── Helper: formato fecha legible ──
  function fmtFecha(fecha) {
    if (!fecha) return '';
    return new Date(fecha + 'T12:00:00').toLocaleDateString('es-ES', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric'
    });
  }

  // ─────────────────────────────────────────────────
  // EMAIL 1: Nueva reserva → restaurante
  // ─────────────────────────────────────────────────
  async function nuevaReserva(reserva) {
    if (!_cfg?.ejs_tpl_restaurante) return { ok: false, reason: 'no_template' };
    const params = {
      to_email:       _cfg.email_notif || _cfg.email || '',
      rest_nombre:    _cfg.nombre || 'Restaurante',
      nombre:         reserva.nombre,
      fecha:          fmtFecha(reserva.fecha),
      hora:           (reserva.hora || '').slice(0, 5),
      personas:       reserva.personas,
      telefono:       reserva.telefono || '—',
      email_cliente:  reserva.email || '—',
      nota:           reserva.nota || '—',
      origen:         reserva.origen || 'web',
      ref:            (reserva.id || '').slice(-8).toUpperCase(),
    };
    return send(_cfg.ejs_tpl_restaurante, params);
  }

  // ─────────────────────────────────────────────────
  // EMAIL 2: Confirmación → cliente
  // ─────────────────────────────────────────────────
  async function confirmacionCliente(reserva) {
    if (!reserva.email) return { ok: false, reason: 'no_client_email' };
    if (!_cfg?.ejs_tpl_cliente) return { ok: false, reason: 'no_template' };
    const params = {
      to_email:          reserva.email,
      to_name:           reserva.nombre,
      rest_nombre:       _cfg.nombre || 'Restaurante',
      rest_dir:          _cfg.dir || '',
      rest_tel:          _cfg.tel || '',
      nombre:            reserva.nombre,
      fecha:             fmtFecha(reserva.fecha),
      hora:              (reserva.hora || '').slice(0, 5),
      personas:          reserva.personas,
      nota:              reserva.nota || '—',
      ref:               (reserva.id || '').slice(-8).toUpperCase(),
      msg_confirmacion:  _cfg.res_msg_confirmacion || '¡Te esperamos!',
      politica:          _cfg.res_politica || '',
    };
    return send(_cfg.ejs_tpl_cliente, params);
  }

  // ─────────────────────────────────────────────────
  // EMAIL 3: Cancelación → restaurante
  // ─────────────────────────────────────────────────
  async function cancelacion(reserva) {
    if (!_cfg?.ejs_tpl_cancelacion) return { ok: false, reason: 'no_template' };
    const params = {
      to_email:    _cfg.email_notif || _cfg.email || '',
      rest_nombre: _cfg.nombre || 'Restaurante',
      nombre:      reserva.nombre,
      fecha:       fmtFecha(reserva.fecha),
      hora:        (reserva.hora || '').slice(0, 5),
      personas:    reserva.personas,
      telefono:    reserva.telefono || '—',
      ref:         (reserva.id || '').slice(-8).toUpperCase(),
    };
    return send(_cfg.ejs_tpl_cancelacion, params);
  }

  // ─────────────────────────────────────────────────
  // EMAIL 4: Recordatorio 24h → cliente
  // Llamado desde el admin (botón manual) o desde
  // una Supabase Edge Function cron
  // ─────────────────────────────────────────────────
  async function recordatorio(reserva) {
    if (!reserva.email) return { ok: false, reason: 'no_client_email' };
    if (!_cfg?.ejs_tpl_recordatorio) return { ok: false, reason: 'no_template' };
    const params = {
      to_email:    reserva.email,
      to_name:     reserva.nombre,
      rest_nombre: _cfg.nombre || 'Restaurante',
      rest_dir:    _cfg.dir || '',
      rest_tel:    _cfg.tel || '',
      nombre:      reserva.nombre,
      fecha:       fmtFecha(reserva.fecha),
      hora:        (reserva.hora || '').slice(0, 5),
      personas:    reserva.personas,
      ref:         (reserva.id || '').slice(-8).toUpperCase(),
    };
    return send(_cfg.ejs_tpl_recordatorio, params);
  }

  return { init, isReady, nuevaReserva, confirmacionCliente, cancelacion, recordatorio };

})();
