#!/usr/bin/env python3
"""
RestaurantePOS — Print Bridge v1.0
====================================
Agente local que corre en el PC del restaurante.
Expone http://localhost:8765 para recibir trabajos de impresión
desde el navegador y enviarlos directamente a la impresora térmica.

INSTALACIÓN:
  pip install pywin32 python-escpos flask flask-cors pyserial
  (En Linux/Mac: pip install python-escpos flask flask-cors pyserial)

USO:
  python pos_print_bridge.py

  Opcional:
  python pos_print_bridge.py --port 8765 --printer "\\\\.\\\USB001"

IMPRESORAS COMPATIBLES:
  - USB (Windows: USB001, USB002... / Linux: /dev/usb/lp0)
  - Red/Ethernet (IP:puerto)
  - Serial/COM (COM1, COM2... / Linux: /dev/ttyUSB0)
  - Bluetooth (puerto COM asignado)

AUTOSTART EN WINDOWS:
  Crea un acceso directo en:
  C:\\Users\\<usuario>\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup
  apuntando a: pythonw pos_print_bridge.py
"""

import sys
import os
import json
import argparse
import logging
import platform
import struct
import socket
import threading
from datetime import datetime

# ── Flask ──
try:
    from flask import Flask, request, jsonify
    from flask_cors import CORS
except ImportError:
    print("ERROR: Instala Flask: pip install flask flask-cors")
    sys.exit(1)

# ── ESC/POS ──
try:
    from escpos.printer import Usb, Network, Serial, File
    ESCPOS_AVAILABLE = True
except ImportError:
    ESCPOS_AVAILABLE = False
    print("AVISO: python-escpos no instalado. Usando modo RAW básico.")

# ─────────────────────────────────────────────────────────────
# CONFIGURACIÓN
# ─────────────────────────────────────────────────────────────

DEFAULT_CONFIG = {
    "port":          8765,
    "printer_type":  "auto",   # auto | usb | network | serial | file
    "printer_target": "",       # IP, COM port, /dev/usb/lp0, etc.
    "printer_port":  9100,      # Para impresoras de red
    "usb_vendor_id": 0x04b8,   # Epson por defecto
    "usb_product_id": 0x0e15,
    "encoding":      "cp850",
    "paper_width":   42,        # caracteres por línea (42=80mm, 32=58mm)
    "cut":           True,
    "beep":          False,
    "debug":         False,
}

CONFIG_FILE = os.path.join(os.path.dirname(__file__), "print_bridge_config.json")

def load_config():
    cfg = DEFAULT_CONFIG.copy()
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE) as f:
                cfg.update(json.load(f))
        except Exception as e:
            print(f"Error leyendo config: {e}")
    return cfg

def save_config(cfg):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(cfg, f, indent=2)

CFG = load_config()

# ─────────────────────────────────────────────────────────────
# ESC/POS COMMANDS
# ─────────────────────────────────────────────────────────────

ESC = b'\x1b'
GS  = b'\x1d'
LF  = b'\x0a'
CR  = b'\x0d'

CMD_INIT         = ESC + b'@'
CMD_CUT_FULL     = GS  + b'V\x00'
CMD_CUT_PARTIAL  = GS  + b'V\x01'
CMD_BEEP         = ESC + b'B\x03\x02'  # 3 beeps, 200ms
CMD_BOLD_ON      = ESC + b'E\x01'
CMD_BOLD_OFF     = ESC + b'E\x00'
CMD_ALIGN_LEFT   = ESC + b'a\x00'
CMD_ALIGN_CENTER = ESC + b'a\x01'
CMD_ALIGN_RIGHT  = ESC + b'a\x02'
CMD_SIZE_NORMAL  = GS  + b'!\x00'
CMD_SIZE_DOUBLE_H= GS  + b'!\x01'
CMD_SIZE_DOUBLE_W= GS  + b'!\x10'
CMD_SIZE_DOUBLE  = GS  + b'!\x11'
CMD_UNDERLINE_ON = ESC + b'-\x01'
CMD_UNDERLINE_OFF= ESC + b'-\x00'
CMD_FEED_N       = lambda n: ESC + b'd' + bytes([n])

def encode_text(text, encoding='cp850'):
    """Encode text for thermal printer, replacing unsupported chars."""
    replacements = {
        'á':'a','é':'e','í':'i','ó':'o','ú':'u',
        'Á':'A','É':'E','Í':'I','Ó':'O','Ú':'U',
        'ñ':'n','Ñ':'N','ü':'u','Ü':'U',
        '€':'EUR','–':'-','—':'-','…':'...',
        '\u00b7':'.', '\u00d7':'x', '\u00f7':'/',
    }
    for k, v in replacements.items():
        text = text.replace(k, v)
    try:
        return text.encode(encoding, errors='replace')
    except Exception:
        return text.encode('ascii', errors='replace')

def center_line(text, width=None):
    w = width or CFG['paper_width']
    if len(text) >= w:
        return text[:w]
    pad = (w - len(text)) // 2
    return ' ' * pad + text

def pad_line(left, right, width=None):
    """Two-column line: left text + right text aligned."""
    w = width or CFG['paper_width']
    space = w - len(left) - len(right)
    if space < 1:
        return left[:w-len(right)-1] + ' ' + right
    return left + ' ' * space + right

def separator(char='─', width=None):
    w = width or CFG['paper_width']
    return char * w

# ─────────────────────────────────────────────────────────────
# TICKET BUILDER
# ─────────────────────────────────────────────────────────────

def build_ticket(data):
    """
    Builds raw ESC/POS bytes from ticket data dict.
    data keys:
      type: 'ticket' | 'comanda' | 'cierre' | 'raw'
      + type-specific fields
    """
    buf = bytearray()
    W   = CFG['paper_width']
    enc = CFG['encoding']

    def add(b):
        buf.extend(b if isinstance(b, (bytes, bytearray)) else encode_text(str(b), enc))

    buf.extend(CMD_INIT)
    buf.extend(CMD_ALIGN_CENTER)

    t = data.get('type', 'ticket')

    # ── TICKET DE COBRO ──
    if t == 'ticket':
        cfg_rest = data.get('cfg', {})
        f        = data.get('factura', {})
        items    = f.get('items', [])

        # Header
        buf.extend(CMD_SIZE_DOUBLE_W)
        buf.extend(CMD_BOLD_ON)
        add(center_line(cfg_rest.get('nombre', 'RESTAURANTE'), W//2 + 2) + '\n')
        buf.extend(CMD_BOLD_OFF)
        buf.extend(CMD_SIZE_NORMAL)

        if cfg_rest.get('dir'):
            add(center_line(cfg_rest['dir']) + '\n')
        if cfg_rest.get('nif'):
            add(center_line('NIF: ' + cfg_rest['nif']) + '\n')
        if cfg_rest.get('tel'):
            add(center_line('Tel: ' + cfg_rest['tel']) + '\n')

        add(separator() + '\n')
        buf.extend(CMD_ALIGN_LEFT)

        # Meta
        now = datetime.now().strftime('%d/%m/%Y  %H:%M')
        add(pad_line('Fecha: ' + now, '', W) + '\n')
        add(pad_line('Factura: ' + str(f.get('num', '')),
                     'Mesa: ' + str(f.get('mesa_num', '?')), W) + '\n')
        add(pad_line('Pago: ' + str(f.get('metodo_pago', '')),
                     'Mesero: ' + str(data.get('user', '')), W) + '\n')

        if f.get('cli_nif'):
            add(separator('-') + '\n')
            add('Cliente: ' + str(f.get('cli_nombre', '')) + '\n')
            add('NIF: '     + str(f.get('cli_nif', ''))    + '\n')

        add(separator() + '\n')

        # Items
        buf.extend(CMD_BOLD_ON)
        add(pad_line('PRODUCTO', 'IMPORTE', W) + '\n')
        buf.extend(CMD_BOLD_OFF)
        add(separator('-') + '\n')

        for item in items:
            name  = str(item.get('name', ''))[:W-10]
            qty   = item.get('qty', 1)
            price = float(item.get('price', 0))
            total = price * qty
            add(pad_line(f'{qty}x {name}', f'{total:.2f}EUR', W) + '\n')
            if item.get('nota'):
                add('  > ' + str(item['nota'])[:W-4] + '\n')

        add(separator() + '\n')

        # Totals
        b10  = float(f.get('base10', 0))
        iva10 = float(f.get('iva10', 0))
        b21  = float(f.get('base21', 0))
        iva21 = float(f.get('iva21', 0))
        total = float(f.get('total', 0))

        if b10 > 0:
            add(pad_line('Base 10%:', f'{b10:.2f}EUR', W) + '\n')
            add(pad_line('IVA 10%:', f'{iva10:.2f}EUR', W) + '\n')
        if b21 > 0:
            add(pad_line('Base 21%:', f'{b21:.2f}EUR', W) + '\n')
            add(pad_line('IVA 21%:', f'{iva21:.2f}EUR', W) + '\n')

        add(separator() + '\n')
        buf.extend(CMD_BOLD_ON)
        buf.extend(CMD_SIZE_DOUBLE_H)
        add(pad_line('TOTAL:', f'{total:.2f}EUR', W) + '\n')
        buf.extend(CMD_SIZE_NORMAL)
        buf.extend(CMD_BOLD_OFF)

        # Efectivo
        if f.get('metodo_pago') == 'efectivo' and data.get('dado'):
            dado   = float(data['dado'])
            cambio = dado - total
            add(pad_line('Entregado:', f'{dado:.2f}EUR', W) + '\n')
            add(pad_line('Cambio:', f'{cambio:.2f}EUR', W) + '\n')

        add(separator() + '\n')
        buf.extend(CMD_ALIGN_CENTER)

        footer = cfg_rest.get('footer', '¡Gracias por su visita!')
        add(footer + '\n')
        add('Factura simplificada\n')
        add('Art.4.1 RD 1619/2012\n')

    # ── COMANDA DE COCINA ──
    elif t == 'comanda':
        mesa    = data.get('mesa', '?')
        items   = data.get('items', [])
        nota    = data.get('nota', '')
        user    = data.get('user', '')
        hora    = datetime.now().strftime('%H:%M')

        buf.extend(CMD_SIZE_DOUBLE)
        buf.extend(CMD_BOLD_ON)
        add('COCINA\n')
        buf.extend(CMD_SIZE_NORMAL)
        buf.extend(CMD_BOLD_OFF)
        add(separator() + '\n')

        buf.extend(CMD_ALIGN_LEFT)
        buf.extend(CMD_BOLD_ON)
        buf.extend(CMD_SIZE_DOUBLE_H)
        add(f'MESA {mesa}     {hora}\n')
        buf.extend(CMD_SIZE_NORMAL)
        buf.extend(CMD_BOLD_OFF)

        if user:
            add(f'Mesero: {user}\n')
        add(separator('-') + '\n')

        for item in items:
            qty  = item.get('qty', 1)
            name = str(item.get('name', ''))
            buf.extend(CMD_BOLD_ON)
            buf.extend(CMD_SIZE_DOUBLE_H)
            add(f'{qty}x  {name[:W-4]}\n')
            buf.extend(CMD_SIZE_NORMAL)
            buf.extend(CMD_BOLD_OFF)
            if item.get('nota'):
                add(f'  ** {item["nota"]}\n')

        if nota:
            add(separator('-') + '\n')
            add(f'NOTA: {nota}\n')

        add(separator() + '\n')

    # ── CIERRE DE CAJA ──
    elif t == 'cierre':
        buf.extend(CMD_BOLD_ON)
        add('CIERRE DE CAJA\n')
        buf.extend(CMD_BOLD_OFF)
        add(separator() + '\n')
        buf.extend(CMD_ALIGN_LEFT)

        for line in data.get('lines', []):
            if line.get('sep'):
                add(separator(line.get('char', '-')) + '\n')
            elif line.get('bold'):
                buf.extend(CMD_BOLD_ON)
                add(pad_line(line.get('left',''), line.get('right',''), W) + '\n')
                buf.extend(CMD_BOLD_OFF)
            else:
                add(pad_line(line.get('left',''), line.get('right',''), W) + '\n')

    # ── RAW TEXT ──
    elif t == 'raw':
        buf.extend(CMD_ALIGN_LEFT)
        add(data.get('text', '') + '\n')

    # Footer feed + cut + optional beep
    buf.extend(CMD_FEED_N(4))
    if CFG.get('cut', True):
        buf.extend(CMD_CUT_PARTIAL)
    if CFG.get('beep', False):
        buf.extend(CMD_BEEP)

    return bytes(buf)

# ─────────────────────────────────────────────────────────────
# PRINTER INTERFACE
# ─────────────────────────────────────────────────────────────

class PrinterError(Exception):
    pass

def detect_printer():
    """Try to auto-detect a connected thermal printer."""
    system = platform.system()

    if system == 'Windows':
        import winreg
        # Check USB printers
        for i in range(1, 10):
            path = f'\\\\.\\USB00{i}'
            try:
                with open(path, 'wb') as f:
                    return ('file', path)
            except:
                pass
        # Check COM ports
        for i in range(1, 10):
            try:
                import serial
                s = serial.Serial(f'COM{i}', 9600, timeout=0.1)
                s.close()
                return ('serial', f'COM{i}')
            except:
                pass

    elif system == 'Linux':
        for dev in ['/dev/usb/lp0', '/dev/usb/lp1', '/dev/lp0']:
            if os.path.exists(dev):
                return ('file', dev)
        for dev in ['/dev/ttyUSB0', '/dev/ttyUSB1', '/dev/ttyS0']:
            if os.path.exists(dev):
                return ('serial', dev)

    elif system == 'Darwin':  # macOS
        for dev in ['/dev/cu.usbmodem1', '/dev/cu.Bluetooth-Incoming-Port']:
            if os.path.exists(dev):
                return ('serial', dev)

    return (None, None)

def send_to_printer(raw_bytes):
    """Send raw ESC/POS bytes to the configured printer."""
    ptype  = CFG.get('printer_type', 'auto')
    target = CFG.get('printer_target', '')

    if ptype == 'auto' or not target:
        ptype, target = detect_printer()
        if not target:
            raise PrinterError('No se encontró ninguna impresora. Configura printer_target en print_bridge_config.json')

    if CFG.get('debug'):
        log(f'Sending {len(raw_bytes)} bytes via {ptype} to {target}')

    # ── Network / Ethernet ──
    if ptype == 'network' or (target and ':' in str(target) and ptype not in ('serial','file')):
        parts = target.split(':')
        host  = parts[0]
        port  = int(parts[1]) if len(parts) > 1 else CFG.get('printer_port', 9100)
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        try:
            s.connect((host, port))
            s.sendall(raw_bytes)
        finally:
            s.close()

    # ── USB / File (Windows USB001, Linux /dev/usb/lp0) ──
    elif ptype in ('usb', 'file') or target.startswith('/dev') or target.startswith('\\\\.\\'):
        with open(target, 'wb') as f:
            f.write(raw_bytes)

    # ── Serial / COM / Bluetooth ──
    elif ptype == 'serial' or target.upper().startswith('COM') or target.startswith('/dev/tty'):
        try:
            import serial
        except ImportError:
            raise PrinterError('Instala pyserial: pip install pyserial')
        baud = CFG.get('baud_rate', 9600)
        with serial.Serial(target, baud, timeout=3) as s:
            s.write(raw_bytes)

    # ── python-escpos USB (by VID/PID) ──
    elif ptype == 'escpos_usb' and ESCPOS_AVAILABLE:
        vid = CFG.get('usb_vendor_id', 0x04b8)
        pid = CFG.get('usb_product_id', 0x0e15)
        p = Usb(vid, pid)
        p._raw(raw_bytes)
        p.close()

    else:
        raise PrinterError(f'Tipo de impresora no reconocido: {ptype} / {target}')

# ─────────────────────────────────────────────────────────────
# FLASK API
# ─────────────────────────────────────────────────────────────

app = Flask(__name__)
CORS(app, origins=['*'])  # Allow from any origin (localhost browser)

log_entries = []

def log(msg):
    ts = datetime.now().strftime('%H:%M:%S')
    entry = f'[{ts}] {msg}'
    print(entry)
    log_entries.append(entry)
    if len(log_entries) > 200:
        log_entries.pop(0)

@app.route('/ping', methods=['GET'])
def ping():
    """Health check — browser polls this to check if bridge is running."""
    ptype, target = detect_printer() if not CFG.get('printer_target') else (CFG.get('printer_type'), CFG.get('printer_target'))
    return jsonify({
        'status':  'ok',
        'version': '1.0',
        'printer': CFG.get('printer_target') or target or 'no detectada',
        'system':  platform.system(),
        'paper':   CFG.get('paper_width', 42),
    })

@app.route('/print', methods=['POST'])
def print_job():
    """Receive a print job and send to printer."""
    data = request.get_json(silent=True) or {}
    job_type = data.get('type', 'unknown')
    mesa     = data.get('mesa') or data.get('factura', {}).get('mesa_num', '?')

    log(f'Trabajo: {job_type} | Mesa {mesa}')

    try:
        raw = build_ticket(data)
        send_to_printer(raw)
        log(f'  ✓ Impreso ({len(raw)} bytes)')
        return jsonify({'ok': True, 'bytes': len(raw)})
    except PrinterError as e:
        log(f'  ✗ Error impresora: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 503
    except Exception as e:
        log(f'  ✗ Error: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500

@app.route('/config', methods=['GET'])
def get_config():
    safe = {k: v for k, v in CFG.items() if 'key' not in k.lower() and 'pass' not in k.lower()}
    return jsonify(safe)

@app.route('/config', methods=['POST'])
def set_config():
    updates = request.get_json(silent=True) or {}
    CFG.update(updates)
    save_config(CFG)
    log(f'Config actualizada: {list(updates.keys())}')
    return jsonify({'ok': True})

@app.route('/test', methods=['POST'])
def test_print():
    """Print a test ticket."""
    data = {
        'type': 'raw',
        'text': (
            '\n'
            + '================================\n'
            + '   RestaurantePOS Print Bridge\n'
            + '         TEST DE IMPRESION\n'
            + '================================\n'
            + f'Sistema: {platform.system()}\n'
            + f'Hora:    {datetime.now().strftime("%d/%m/%Y %H:%M:%S")}\n'
            + f'Papel:   {CFG.get("paper_width",42)} columnas\n'
            + '================================\n'
            + '  Si ves esto, funciona bien!\n'
            + '================================\n'
        )
    }
    try:
        raw = build_ticket(data)
        send_to_printer(raw)
        return jsonify({'ok': True})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500

@app.route('/log', methods=['GET'])
def get_log():
    return jsonify({'log': log_entries[-50:]})

@app.route('/detect', methods=['GET'])
def detect():
    ptype, target = detect_printer()
    return jsonify({'type': ptype, 'target': target})

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='RestaurantePOS Print Bridge')
    parser.add_argument('--port',    type=int,   default=CFG['port'],           help='Puerto HTTP (defecto 8765)')
    parser.add_argument('--printer', type=str,   default=CFG['printer_target'], help='Impresora (IP, COM, /dev/usb/lp0)')
    parser.add_argument('--type',    type=str,   default=CFG['printer_type'],   help='Tipo: auto|network|usb|serial|file')
    parser.add_argument('--width',   type=int,   default=CFG['paper_width'],    help='Columnas papel (42=80mm, 32=58mm)')
    parser.add_argument('--nocut',   action='store_true',                        help='No cortar papel')
    parser.add_argument('--beep',    action='store_true',                        help='Pitido al imprimir')
    parser.add_argument('--debug',   action='store_true',                        help='Modo debug')
    args = parser.parse_args()

    CFG['port']           = args.port
    CFG['printer_target'] = args.printer
    CFG['printer_type']   = args.type
    CFG['paper_width']    = args.width
    CFG['cut']            = not args.nocut
    CFG['beep']           = args.beep
    CFG['debug']          = args.debug

    print('=' * 50)
    print('  RestaurantePOS — Print Bridge v1.0')
    print('=' * 50)
    print(f'  Puerto:      http://localhost:{CFG["port"]}')
    print(f'  Impresora:   {CFG["printer_target"] or "auto-detectar"}')
    print(f'  Tipo:        {CFG["printer_type"]}')
    print(f'  Papel:       {CFG["paper_width"]} cols')
    print(f'  Corte:       {"SI" if CFG["cut"] else "NO"}')
    print(f'  Sistema:     {platform.system()}')
    print('=' * 50)
    print()

    # Auto-detect on startup
    if not CFG['printer_target']:
        ptype, target = detect_printer()
        if target:
            print(f'  ✓ Impresora detectada: {ptype} → {target}')
        else:
            print('  ⚠ No se detectó impresora automáticamente.')
            print('    Configura printer_target en print_bridge_config.json')
            print('    o pasa --printer <destino>')
    print()
    print('  Bridge activo. Mantén esta ventana abierta.')
    print('  El navegador se conectará automáticamente.')
    print()

    app.run(
        host='127.0.0.1',
        port=CFG['port'],
        debug=False,
        threaded=True,
        use_reloader=False,
    )
