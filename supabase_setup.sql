-- ============================================================
-- RestaurantePOS — Script de inicialización Supabase
-- Ejecutar en: SQL Editor → New query → Run
-- ============================================================

-- ────────────────────────────────────────
-- 1. CONFIGURACIÓN
-- ────────────────────────────────────────
-- Habilitar extensión para UUIDs
create extension if not exists "pgcrypto";


-- ────────────────────────────────────────
-- 2. TABLA: pos_config
-- Configuración global del restaurante (1 sola fila)
-- ────────────────────────────────────────
create table if not exists pos_config (
  id          serial primary key,
  nombre      text    not null default 'Restaurante Madrid',
  nif         text    not null default 'B12345678',
  dir         text    default '',
  cp          text    default '28013 Madrid',
  tel         text    default '',
  email       text    default '',
  iva1        numeric default 10,   -- IVA comida / sin alcohol (Art. 91 LIVA)
  iva2        numeric default 21,   -- IVA bebidas alcohólicas
  serie       text    default 'T',  -- Serie de facturación (RD 1619/2012)
  lastnum     integer default 0,    -- Último número de ticket emitido
  footer      text    default '¡Gracias por su visita! IVA incluido.',
  qr          boolean default true,
  menu_precio numeric default 12.50,
  menu_bebida boolean default true,
  updated_at  timestamptz default now()
);

-- Fila única garantizada
insert into pos_config (id) values (1)
on conflict (id) do nothing;


-- ────────────────────────────────────────
-- 3. TABLA: pos_users
-- Usuarios del sistema con roles y PINs
-- ────────────────────────────────────────
create table if not exists pos_users (
  id         text primary key default gen_random_uuid()::text,
  nombre     text    not null,
  rol        text    not null default 'camarero'
               check (rol in ('admin','gerente','camarero','cocina','caja')),
  pin        text    not null,           -- 4 dígitos, se guarda en claro (offline app)
  avatar     text    default '',
  activo     boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Usuario administrador por defecto (PIN: 1234)
insert into pos_users (id, nombre, rol, pin, avatar)
values ('u-admin-default', 'Administrador', 'admin', '1234', 'A')
on conflict (id) do nothing;


-- ────────────────────────────────────────
-- 4. TABLA: pos_zonas
-- Zonas del restaurante (Interior, Terraza, Barra…)
-- ────────────────────────────────────────
create table if not exists pos_zonas (
  id         text primary key default gen_random_uuid()::text,
  nombre     text not null unique,
  icon       text default '🏠',
  orden      integer default 99,
  created_at timestamptz default now()
);

insert into pos_zonas (id, nombre, icon, orden) values
  ('z-interior', 'Interior', '🏠', 1),
  ('z-terraza',  'Terraza',  '🌿', 2),
  ('z-barra',    'Barra',    '☕', 3),
  ('z-vip',      'VIP',      '⭐', 4)
on conflict (id) do nothing;


-- ────────────────────────────────────────
-- 5. TABLA: pos_mesas
-- Mesas del restaurante
-- ────────────────────────────────────────
create table if not exists pos_mesas (
  id         text primary key default gen_random_uuid()::text,
  num        integer not null unique,
  zona_id    text references pos_zonas(id) on delete set null,
  cap        integer default 4,
  icon       text    default '🪑',
  activa     boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

insert into pos_mesas (id, num, zona_id, cap, icon) values
  ('m-1', 1, 'z-interior', 4, '🪑'),
  ('m-2', 2, 'z-interior', 4, '🪑'),
  ('m-3', 3, 'z-interior', 2, '🪑'),
  ('m-4', 4, 'z-interior', 6, '🪑'),
  ('m-5', 5, 'z-interior', 4, '🪑'),
  ('m-6', 6, 'z-terraza',  4, '🌿'),
  ('m-7', 7, 'z-terraza',  4, '🌿'),
  ('m-8', 8, 'z-barra',    2, '☕'),
  ('m-9', 9, 'z-vip',      8, '⭐')
on conflict (id) do nothing;


-- ────────────────────────────────────────
-- 6. TABLA: pos_cats
-- Categorías de la carta
-- ────────────────────────────────────────
create table if not exists pos_cats (
  id         text primary key default gen_random_uuid()::text,
  nombre     text not null,
  emoji      text default '🍽️',
  orden      integer default 99,
  activa     boolean default true,
  created_at timestamptz default now()
);

insert into pos_cats (id, nombre, emoji, orden) values
  ('ct-menu',       'Menú del día', '🍽️', 1),
  ('ct-entrantes',  'Entrantes',    '🥗', 2),
  ('ct-principales','Principales',  '🍲', 3),
  ('ct-postres',    'Postres',      '🍰', 4),
  ('ct-bebidas',    'Bebidas',      '🥤', 5)
on conflict (id) do nothing;


-- ────────────────────────────────────────
-- 7. TABLA: pos_carta
-- Productos de la carta
-- ────────────────────────────────────────
create table if not exists pos_carta (
  id         text primary key default gen_random_uuid()::text,
  cat_id     text references pos_cats(id) on delete set null,
  name       text    not null,
  emoji      text    default '🍽️',
  descripcion text    default '',
  price      numeric not null default 0,
  iva        integer not null default 10   -- 10 o 21 según normativa
               check (iva in (0, 10, 21)),
  tag        text    check (tag in ('popular','vegano','nuevo') or tag is null),
  active     boolean default true,
  orden      integer default 99,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

insert into pos_carta (id, cat_id, name, emoji, descripcion, price, iva, tag) values
  ('c-1',  'ct-menu',       'Menú completo (1º+2º+postre+bebida)', '🍽️', 'Pan incluido',                  12.50, 10, 'popular'),
  ('c-2',  'ct-menu',       'Solo primero y segundo',               '🥣', 'Sin postre ni bebida',           10.00, 10, null),
  ('c-3',  'ct-entrantes',  'Croquetas caseras',                    '🧆', 'Jamón ibérico, bechamel casera', 7.50, 10, 'popular'),
  ('c-4',  'ct-entrantes',  'Patatas bravas',                       '🥔', 'Salsa alioli y brava casera',     5.00, 10, 'vegano'),
  ('c-5',  'ct-entrantes',  'Tabla de embutidos ibéricos',          '🥩', 'Jamón, lomo, chorizo',           14.00, 10, null),
  ('c-6',  'ct-entrantes',  'Ensalada César',                       '🥗', 'Pollo, parmesano, anchoas',       9.00, 10, null),
  ('c-7',  'ct-principales','Cocido madrileño',                     '🍲', 'Garbanzos, carne y verduras',    16.00, 10, 'popular'),
  ('c-8',  'ct-principales','Callos a la madrileña',                '🥘', 'Receta tradicional',             14.50, 10, null),
  ('c-9',  'ct-principales','Solomillo a la plancha',               '🥩', '250g con guarnición',            22.00, 10, null),
  ('c-10', 'ct-principales','Merluza al horno',                     '🐟', 'Con verduras de temporada',      18.00, 10, null),
  ('c-11', 'ct-principales','Pasta del día',                        '🍝', 'Consultar elaboración',          11.00, 10, 'nuevo'),
  ('c-12', 'ct-postres',    'Tarta de queso',                       '🍰', 'Casera, coulis de frutos rojos',  5.50, 10, 'popular'),
  ('c-13', 'ct-postres',    'Flan de huevo',                        '🍮', 'Con nata',                        4.00, 10, null),
  ('c-14', 'ct-postres',    'Helado (3 bolas)',                     '🍨', 'Varios sabores',                  4.50, 10, null),
  ('c-15', 'ct-postres',    'Fruta de temporada',                   '🍊', '',                                3.50, 10, 'vegano'),
  ('c-16', 'ct-bebidas',    'Agua mineral (50cl)',                  '💧', 'Con o sin gas',                   1.80, 10, null),
  ('c-17', 'ct-bebidas',    'Refresco',                             '🥤', 'Cola, naranja, limón',            2.50, 10, null),
  ('c-18', 'ct-bebidas',    'Zumo natural',                         '🍊', 'Naranja o mango',                 3.00, 10, null),
  ('c-19', 'ct-bebidas',    'Café solo',                            '☕', '',                                1.50, 10, null),
  ('c-20', 'ct-bebidas',    'Café con leche',                       '☕', '',                                1.80, 10, null),
  ('c-21', 'ct-bebidas',    'Caña de cerveza',                      '🍺', '33cl',                            2.20, 21, null),
  ('c-22', 'ct-bebidas',    'Copa de vino tinto',                   '🍷', 'Ribera del Duero',                3.50, 21, null),
  ('c-23', 'ct-bebidas',    'Copa de vino blanco',                  '🥂', 'Rueda verdejo',                   3.50, 21, null),
  ('c-24', 'ct-bebidas',    'Botella vino (75cl)',                  '🍾', 'Selección de la casa',           16.00, 21, null),
  ('c-25', 'ct-bebidas',    'Gin tonic',                            '🍸', 'Gin premium + tónica artesanal',  9.00, 21, null)
on conflict (id) do nothing;


-- ────────────────────────────────────────
-- 8. TABLA: pos_pedidos
-- Pedidos activos en mesas (se borran al cobrar)
-- ────────────────────────────────────────
create table if not exists pos_pedidos (
  id          text primary key default gen_random_uuid()::text,
  mesa_id     text references pos_mesas(id) on delete cascade,
  mesa_num    integer not null,
  items       jsonb   not null default '[]',  -- array de líneas de pedido
  estado      text    not null default 'abierto'
                check (estado in ('abierto','en-cocina','listo','pagado','cancelado')),
  nota        text    default '',
  user_id     text    references pos_users(id) on delete set null,  -- camarero responsable
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- Índice para consultas por mesa
create index if not exists idx_pedidos_mesa on pos_pedidos(mesa_id);
create index if not exists idx_pedidos_estado on pos_pedidos(estado);


-- ────────────────────────────────────────
-- 9. TABLA: pos_facturas
-- Registro permanente de tickets emitidos
-- (no se borra nunca — obligatorio 4 años según Ley 58/2003)
-- ────────────────────────────────────────
create table if not exists pos_facturas (
  id          text primary key default gen_random_uuid()::text,
  num         text not null unique,    -- Serie + número correlativo (ej: T000001)
  pedido_id   text,                    -- Referencia al pedido (puede ser null si ya se eliminó)
  mesa_num    integer,
  items       jsonb not null default '[]',
  metodo_pago text not null default 'efectivo'
                check (metodo_pago in ('efectivo','tarjeta','bizum','otro')),
  base10      numeric default 0,      -- Base imponible IVA 10%
  iva10       numeric default 0,      -- Cuota IVA 10%
  base21      numeric default 0,      -- Base imponible IVA 21%
  iva21       numeric default 0,      -- Cuota IVA 21%
  total       numeric not null,
  -- Datos del cliente (factura completa opcional, RD 1619/2012)
  cli_nombre  text default '',
  cli_nif     text default '',
  cli_dir     text default '',
  user_id     text,                   -- Camarero que cobró
  created_at  timestamptz default now()
);

create index if not exists idx_facturas_fecha on pos_facturas(created_at);
create index if not exists idx_facturas_num   on pos_facturas(num);


-- ────────────────────────────────────────
-- 10. TABLA: pos_caja
-- Aperturas y cierres de caja (para el siguiente módulo)
-- ────────────────────────────────────────
create table if not exists pos_caja (
  id              text primary key default gen_random_uuid()::text,
  tipo            text not null check (tipo in ('apertura','cierre')),
  user_id         text references pos_users(id) on delete set null,
  fondo_inicial   numeric default 0,   -- Efectivo al abrir caja
  efectivo_real   numeric,             -- Efectivo contado al cerrar
  total_efectivo  numeric default 0,   -- Vendido en efectivo según sistema
  total_tarjeta   numeric default 0,
  total_bizum     numeric default 0,
  total_ventas    numeric default 0,
  num_tickets     integer default 0,
  diferencia      numeric,             -- efectivo_real - (fondo_inicial + total_efectivo)
  nota            text default '',
  created_at      timestamptz default now()
);


-- ────────────────────────────────────────
-- 11. ROW LEVEL SECURITY (RLS)
-- Habilitado pero permisivo para uso en red local
-- (la autenticación la gestiona el PIN, no Supabase Auth)
-- ────────────────────────────────────────
alter table pos_config   enable row level security;
alter table pos_users    enable row level security;
alter table pos_zonas    enable row level security;
alter table pos_mesas    enable row level security;
alter table pos_cats     enable row level security;
alter table pos_carta    enable row level security;
alter table pos_pedidos  enable row level security;
alter table pos_facturas enable row level security;
alter table pos_caja     enable row level security;

-- Política: la anon key puede leer y escribir todo
-- (el control de acceso lo hace el PIN en el frontend)
create policy "anon_all_config"   on pos_config   for all to anon using (true) with check (true);
create policy "anon_all_users"    on pos_users     for all to anon using (true) with check (true);
create policy "anon_all_zonas"    on pos_zonas     for all to anon using (true) with check (true);
create policy "anon_all_mesas"    on pos_mesas     for all to anon using (true) with check (true);
create policy "anon_all_cats"     on pos_cats      for all to anon using (true) with check (true);
create policy "anon_all_carta"    on pos_carta     for all to anon using (true) with check (true);
create policy "anon_all_pedidos"  on pos_pedidos   for all to anon using (true) with check (true);
create policy "anon_all_facturas" on pos_facturas  for all to anon using (true) with check (true);
create policy "anon_all_caja"     on pos_caja      for all to anon using (true) with check (true);


-- ────────────────────────────────────────
-- 12. REALTIME
-- Activar publicación en tiempo real para las tablas críticas
-- ────────────────────────────────────────
alter publication supabase_realtime add table pos_pedidos;
alter publication supabase_realtime add table pos_config;
alter publication supabase_realtime add table pos_carta;
alter publication supabase_realtime add table pos_mesas;
alter publication supabase_realtime add table pos_zonas;
alter publication supabase_realtime add table pos_cats;


-- ────────────────────────────────────────
-- 13. FUNCIÓN: actualizar updated_at automáticamente
-- ────────────────────────────────────────
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_config_updated   before update on pos_config   for each row execute function update_updated_at();
create trigger trg_users_updated    before update on pos_users     for each row execute function update_updated_at();
create trigger trg_mesas_updated    before update on pos_mesas     for each row execute function update_updated_at();
create trigger trg_carta_updated    before update on pos_carta     for each row execute function update_updated_at();
create trigger trg_pedidos_updated  before update on pos_pedidos   for each row execute function update_updated_at();


-- ────────────────────────────────────────
-- VERIFICACIÓN FINAL
-- Ejecuta esto después para confirmar que todo está bien
-- ────────────────────────────────────────
select
  schemaname,
  tablename,
  rowsecurity
from pg_tables
where tablename like 'pos_%'
order by tablename;
