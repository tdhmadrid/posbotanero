/**
 * RestaurantePOS — Print Client v1.0
 * =====================================
 * Módulo JS que intenta imprimir vía el bridge local (pos_print_bridge.py).
 * Si el bridge no está activo, usa window.print() como fallback.
 *
 * Incluir en cada módulo:
 *   <script src="pos_print_client.js"></script>
 *   O copiar el contenido inline.
 */

'use strict';

const PosPrint = (() => {

  const BRIDGE_URL = 'http://localhost:8765';
  const TIMEOUT_MS = 1500;

  let _bridgeAvailable = null;  // null=unknown, true/false
  let _lastCheck = 0;
  const CHECK_INTERVAL = 30000; // re-check every 30s

  // ─── BRIDGE CHECK ───
  async function checkBridge() {
    const now = Date.now();
    if (_bridgeAvailable !== null && (now - _lastCheck) < CHECK_INTERVAL) {
      return _bridgeAvailable;
    }
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
      const res = await fetch(BRIDGE_URL + '/ping', {
        signal: ctrl.signal,
        cache: 'no-store',
      });
      clearTimeout(timer);
      _bridgeAvailable = res.ok;
      _lastCheck = now;
      if (_bridgeAvailable) {
        const info = await res.json();
        console.log('[PosPrint] Bridge activo →', info.printer);
      }
    } catch (_) {
      _bridgeAvailable = false;
      _lastCheck = now;
    }
    return _bridgeAvailable;
  }

  // ─── SEND TO BRIDGE ───
  async function sendToBridge(data) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 5000);
    try {
      const res = await fetch(BRIDGE_URL + '/print', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
        signal: ctrl.signal,
      });
      clearTimeout(timer);
      const result = await res.json();
      if (!result.ok) throw new Error(result.error || 'Error de impresión');
      return true;
    } catch (e) {
      clearTimeout(timer);
      throw e;
    }
  }

  // ─── FALLBACK: browser window.print() ───
  function browserPrint(htmlContent) {
    const el = document.getElementById('ticketPrint');
    if (el) el.innerHTML = htmlContent;
    window.print();
  }

  // ─── TICKET DE COBRO ───
  async function ticket(factura, cfg, userNombre, efectivoDado) {
    const data = {
      type:    'ticket',
      factura: factura,
      cfg:     cfg || {},
      user:    userNombre || '',
      dado:    efectivoDado || 0,
    };

    const via = await checkBridge();
    if (via) {
      try {
        await sendToBridge(data);
        return { ok: true, via: 'bridge' };
      } catch (e) {
        console.warn('[PosPrint] Bridge falló, usando browser print:', e.message);
        _bridgeAvailable = false;
      }
    }

    // Fallback HTML
    browserPrint(buildTicketHtml(factura, cfg, userNombre, efectivoDado));
    return { ok: true, via: 'browser' };
  }

  // ─── COMANDA DE COCINA ───
  async function comanda(mesaNum, items, nota, userNombre) {
    const data = {
      type:  'comanda',
      mesa:  mesaNum,
      items: items || [],
      nota:  nota  || '',
      user:  userNombre || '',
    };

    const via = await checkBridge();
    if (via) {
      try {
        await sendToBridge(data);
        return { ok: true, via: 'bridge' };
      } catch (e) {
        console.warn('[PosPrint] Bridge falló:', e.message);
        _bridgeAvailable = false;
      }
    }

    // Fallback
    browserPrint(buildComandaHtml(mesaNum, items, nota, userNombre));
    return { ok: true, via: 'browser' };
  }

  // ─── CIERRE DE CAJA ───
  async function cierreCaja(lines) {
    const data = { type: 'cierre', lines: lines || [] };

    const via = await checkBridge();
    if (via) {
      try {
        await sendToBridge(data);
        return { ok: true, via: 'bridge' };
      } catch (e) {
        _bridgeAvailable = false;
      }
    }

    browserPrint(buildCierreHtml(lines));
    return { ok: true, via: 'browser' };
  }

  // ─── TEST ───
  async function test() {
    try {
      const res = await fetch(BRIDGE_URL + '/test', { method: 'POST' });
      const result = await res.json();
      return result;
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  // ─── STATUS ───
  async function status() {
    try {
      const res = await fetch(BRIDGE_URL + '/ping', { cache: 'no-store' });
      return await res.json();
    } catch (_) {
      return { status: 'offline' };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // HTML FALLBACK BUILDERS
  // ═══════════════════════════════════════════════════════════

  const TICKET_CSS = `
    @media print {
      body > *:not(#ticketPrint) { display: none !important; }
      #ticketPrint { display: block !important; }
    }
    .ticket {
      font-family: 'Courier New', monospace;
      font-size: 12px;
      width: 280px;
      margin: 0 auto;
      color: #000;
    }
    .t-center { text-align: center; }
    .t-logo   { font-size: 16px; font-weight: 700; margin: 6px 0; }
    .t-row    { display: flex; justify-content: space-between; margin: 2px 0; }
    .t-total  { display: flex; justify-content: space-between; font-weight: 700; font-size: 15px; margin: 4px 0; }
    .t-sep    { border: none; border-top: 1px dashed #999; margin: 5px 0; }
    .t-foot   { font-size: 10px; color: #555; text-align: center; margin-top: 4px; }
    .t-bold   { font-weight: 700; }
    .t-big    { font-size: 18px; font-weight: 700; }
  `;

  function buildTicketHtml(f, cfg, user, dado) {
    const items  = (f.items || []).map(i =>
      `<div class="t-row"><span>${i.name.substring(0,20)} ×${i.qty}</span><span>${(i.price*i.qty).toFixed(2)}€</span></div>`
    ).join('');

    const b10  = Number(f.base10 || 0);
    const iva10 = Number(f.iva10 || 0);
    const b21  = Number(f.base21 || 0);
    const iva21 = Number(f.iva21 || 0);
    const total = Number(f.total || 0);

    const cambioHtml = (f.metodo_pago === 'efectivo' && dado)
      ? `<div class="t-row"><span>Entregado:</span><span>${Number(dado).toFixed(2)}€</span></div>
         <div class="t-row"><span>Cambio:</span><span>${(dado-total).toFixed(2)}€</span></div>`
      : '';

    const cliHtml = f.cli_nif
      ? `<hr class="t-sep"><div>${f.cli_nombre || ''} · NIF: ${f.cli_nif}</div>`
      : '';

    const now = new Date().toLocaleString('es-ES', {day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'});

    return `<style>${TICKET_CSS}</style>
    <div class="ticket">
      <div class="t-center t-logo">${cfg.nombre || 'RESTAURANTE'}</div>
      <div class="t-center">${cfg.dir || ''}</div>
      <div class="t-center">${cfg.nif ? 'NIF: '+cfg.nif : ''}</div>
      <hr class="t-sep">
      <div class="t-row"><span>${now}</span><span>Mesa ${f.mesa_num || '?'}</span></div>
      <div class="t-row"><span>Factura: <b>${f.num}</b></span><span>${f.metodo_pago}</span></div>
      ${cliHtml}
      <hr class="t-sep">
      ${items}
      <hr class="t-sep">
      ${b10>0?`<div class="t-row"><span>Base 10%</span><span>${b10.toFixed(2)}€</span></div>
               <div class="t-row"><span>IVA 10%</span><span>${iva10.toFixed(2)}€</span></div>`:''}
      ${b21>0?`<div class="t-row"><span>Base 21%</span><span>${b21.toFixed(2)}€</span></div>
               <div class="t-row"><span>IVA 21%</span><span>${iva21.toFixed(2)}€</span></div>`:''}
      <hr class="t-sep">
      <div class="t-total"><span>TOTAL</span><span>${total.toFixed(2)}€</span></div>
      ${cambioHtml}
      <hr class="t-sep">
      <div class="t-foot">${cfg.footer || '¡Gracias por su visita!'}</div>
      <div class="t-foot">Factura simplificada · Art.4.1 RD 1619/2012</div>
    </div>`;
  }

  function buildComandaHtml(mesa, items, nota, user) {
    const hora = new Date().toLocaleTimeString('es-ES', {hour:'2-digit',minute:'2-digit'});
    const rows = (items || []).map(i =>
      `<div style="margin:6px 0">
        <div class="t-bold" style="font-size:15px">${i.qty}×  ${i.name}</div>
        ${i.nota ? `<div style="padding-left:12px">» ${i.nota}</div>` : ''}
       </div><hr class="t-sep">`
    ).join('');

    return `<style>${TICKET_CSS}</style>
    <div class="ticket">
      <div class="t-center t-logo">COCINA</div>
      <hr class="t-sep">
      <div class="t-big">MESA ${mesa} &nbsp;&nbsp;&nbsp; ${hora}</div>
      ${user ? `<div>Mesero: ${user}</div>` : ''}
      <hr class="t-sep">
      ${rows}
      ${nota ? `<div>NOTA: <b>${nota}</b></div>` : ''}
    </div>`;
  }

  function buildCierreHtml(lines) {
    const rows = (lines || []).map(l => {
      if (l.sep) return `<hr class="t-sep">`;
      const cls = l.bold ? ' class="t-bold"' : '';
      return `<div class="t-row"${cls}><span>${l.left||''}</span><span>${l.right||''}</span></div>`;
    }).join('');

    return `<style>${TICKET_CSS}</style>
    <div class="ticket">
      <div class="t-center t-logo">CIERRE DE CAJA</div>
      <hr class="t-sep">
      ${rows}
    </div>`;
  }

  // ─── PUBLIC API ───
  return { ticket, comanda, cierreCaja, test, status, checkBridge };

})();
