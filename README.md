# RestaurantePOS

Sistema TPV completo para restaurante informal. Funciona en red local con múltiples dispositivos sincronizados via Supabase Realtime. Sin dependencias, sin build steps — HTML puro.

## Archivos

| Archivo | Descripción | Dispositivo |
|---|---|---|
| `pos_core.html` | TPV principal — mesas, pedidos, cobro, caja | Tablet mostrador |
| `pos_admin.html` | Panel admin — usuarios, mesas, carta, config | PC back-office |
| `pos_kds.html` | Kitchen Display System | Tablet cocina |
| `pos_qr.html?mesa=N` | Carta digital para cliente | Móvil cliente |
| `supabase_setup.sql` | Script de inicialización de base de datos | Supabase SQL Editor |

## Setup rápido

### 1. Base de datos

1. Crea un proyecto en [supabase.com](https://supabase.com)
2. Ve a **SQL Editor → New query**
3. Pega el contenido de `supabase_setup.sql` y pulsa **Run**

### 2. Credenciales

Las credenciales de Supabase están en el bloque `SUPABASE CONFIG` al inicio del `<script>` de cada archivo:

```js
const SUPA_URL = 'https://TU_PROYECTO.supabase.co';
const SUPA_KEY = 'eyJ...tu_anon_key...';
```

### 3. Primer acceso

- Abre `pos_admin.html` → PIN por defecto: **1234**
- Ve a **Configuración** → rellena los datos fiscales de tu negocio
- Crea los usuarios del equipo con sus PINs y roles

## Roles de usuario

| Rol | Acceso |
|---|---|
| `admin` | Acceso total + configuración |
| `gerente` | Sin config fiscal, con facturas y caja |
| `camarero` | Pedidos, cobro, mesas |
| `cocina` | Solo KDS |
| `caja` | Solo cobro y caja |

## Tecnología

- **Frontend**: HTML + CSS + JavaScript vanilla (sin frameworks)
- **Base de datos**: Supabase (PostgreSQL)
- **Sincronización**: Supabase Realtime (WebSocket) + polling de respaldo
- **Impresión**: `window.print()` con CSS para tickets 80mm

## Normativa fiscal (España)

- IVA 10% — comida y bebidas sin alcohol (Art. 91 LIVA)
- IVA 21% — bebidas alcohólicas
- Numeración correlativa por serie (RD 1619/2012)
- Factura simplificada válida hasta 3.000€
- Retención de facturas: tablas `pos_facturas` y `pos_caja` nunca se borran

## Deploy

Ver guía en el README o desplegar directamente en Netlify arrastrando la carpeta.

[![Deploy to Netlify](https://www.netlify.com/img/deploy/button.svg)](https://app.netlify.com/start)

## Licencia

Uso privado. No distribuir sin autorización.
