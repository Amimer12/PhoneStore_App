-- ============================================================
-- SHOP DATABASE SCHEMA (Supabase / PostgreSQL)
-- Perfume + Electronics shop management
-- ============================================================

-- ---------- 1. CATEGORIES (Perfum / Electronics) ----------
create table categories (
  id bigint generated always as identity primary key,
  name varchar(50) not null unique,
  image_url text,
  created_at timestamptz not null default now()
);

-- ---------- 2. PRODUCT TYPES (self-referencing tree) ----------
-- One table handles type1 -> type2 -> type3 (and beyond, if you ever need it)
-- e.g. Electronics > Chargers > iPhone
--      Electronics > Cables > TypeC > TypeC-to-TypeC
--      Electronics > Flexy > Ooredoo
create table product_types (
  id bigint generated always as identity primary key,
  category_id bigint not null references categories(id) on delete cascade,
  parent_id bigint references product_types(id) on delete cascade,
  name varchar(50) not null,
  image_url text,
  level smallint not null default 1, -- 1 = top type under category, 2 = sub type, 3 = sub-sub type
  created_at timestamptz not null default now(),
  unique (category_id, parent_id, name)
);
create index idx_product_types_parent on product_types(parent_id);
create index idx_product_types_category on product_types(category_id);

-- ---------- 3. MARQUES (brands) ----------
create table marques (
  id bigint generated always as identity primary key,
  name varchar(50) not null unique,
  image_url text,
  created_at timestamptz not null default now()
);

-- ---------- 4. PRODUCTS ----------
create table products (
  id bigint generated always as identity primary key,
  name varchar(100),                       -- optional free label, e.g. "iPhone 13 fast charger"
  category_id bigint not null references categories(id),
  type1_id bigint not null references product_types(id),
  type2_id bigint references product_types(id),
  type3_id bigint references product_types(id),
  marque_id bigint references marques(id),
  prix integer not null check (prix >= 0), -- price in your currency's smallest unit you prefer (e.g. DZD)
  stock integer not null default 0,
  image_url text,
  created_at timestamptz not null default now()
);
create index idx_products_type1 on products(type1_id);
create index idx_products_category on products(category_id);
create index idx_products_marque on products(marque_id);

-- ---------- 5. ACHATS (sales/purchases) ----------
create table achats (
  id bigint generated always as identity primary key,
  achat_date date not null default current_date,
  achat_time time not null default current_time,
  total_price integer not null default 0,
  created_at timestamptz not null default now()
);

create table achat_items (
  id bigint generated always as identity primary key,
  achat_id bigint not null references achats(id) on delete cascade,
  product_id bigint not null references products(id),
  quantity integer not null check (quantity > 0),
  unit_price integer not null,             -- snapshot of price at time of sale
  subtotal integer generated always as (quantity * unit_price) stored
);
create index idx_achat_items_achat on achat_items(achat_id);
create index idx_achat_items_product on achat_items(product_id);

-- keep achats.total_price in sync automatically
create or replace function refresh_achat_total()
returns trigger as $$
begin
  update achats
  set total_price = coalesce((
    select sum(subtotal) from achat_items where achat_id = coalesce(new.achat_id, old.achat_id)
  ), 0)
  where id = coalesce(new.achat_id, old.achat_id);
  return null;
end;
$$ language plpgsql;

create trigger trg_achat_items_after_change
after insert or update or delete on achat_items
for each row execute function refresh_achat_total();

-- also decrement stock automatically when an achat_item is added
create or replace function decrement_stock()
returns trigger as $$
begin
  update products set stock = stock - new.quantity where id = new.product_id;
  return new;
end;
$$ language plpgsql;

create trigger trg_achat_items_stock
after insert on achat_items
for each row execute function decrement_stock();

-- ---------- 6. PROFILES (admin vs worker, for auth/RLS) ----------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role varchar(10) not null default 'worker' check (role in ('admin', 'worker')),
  created_at timestamptz not null default now()
);

-- ============================================================
-- ANALYTICS VIEWS (used by the "Analyse" page)
-- ============================================================
create or replace view v_daily_revenue as
select achat_date, sum(total_price) as revenue, count(*) as nb_achats
from achats
group by achat_date
order by achat_date;

create or replace view v_top_products as
select p.id, p.name, p.image_url,
       sum(ai.quantity) as total_qty,
       sum(ai.subtotal) as total_revenue
from achat_items ai
join products p on p.id = ai.product_id
group by p.id, p.name, p.image_url
order by total_revenue desc;

create or replace view v_revenue_by_category as
select c.name as category, sum(ai.subtotal) as revenue
from achat_items ai
join products p on p.id = ai.product_id
join categories c on c.id = p.category_id
group by c.name;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table categories enable row level security;
alter table product_types enable row level security;
alter table marques enable row level security;
alter table products enable row level security;
alter table achats enable row level security;
alter table achat_items enable row level security;
alter table profiles enable row level security;

-- Everyone logged in can read catalog data
create policy "read catalog" on categories for select using (auth.role() = 'authenticated');
create policy "read types" on product_types for select using (auth.role() = 'authenticated');
create policy "read marques" on marques for select using (auth.role() = 'authenticated');
create policy "read products" on products for select using (auth.role() = 'authenticated');

-- Only admins can write catalog data
create policy "admin write categories" on categories for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "admin write types" on product_types for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "admin write marques" on marques for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "admin write products" on products for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- Workers AND admins can create/view achats (sales happen on the floor)
create policy "read achats" on achats for select using (auth.role() = 'authenticated');
create policy "insert achats" on achats for insert with check (auth.role() = 'authenticated');
create policy "admin update achats" on achats for update
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "admin delete achats" on achats for delete
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

create policy "read achat_items" on achat_items for select using (auth.role() = 'authenticated');
create policy "insert achat_items" on achat_items for insert with check (auth.role() = 'authenticated');
create policy "admin update achat_items" on achat_items for update
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "admin delete achat_items" on achat_items for delete
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

create policy "self profile" on profiles for select using (auth.uid() = id);
