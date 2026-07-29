# Shop Admin — Perfume & Electronics

Flutter admin app (Products / Achats / Analyse) backed by Supabase.

## What's in here
```
sql/schema.sql          -> run this in Supabase SQL editor (tables, triggers, views, RLS)
sql/STORAGE_SETUP.md     -> storage bucket + policies for product/category/type/marque images
flutter_app/             -> the Flutter project
```

## Data model summary
- `categories`: Perfum, Electronics.
- `product_types`: **self-referencing tree** (`parent_id`). This is the key design choice:
  instead of separate type/type2/type3 columns per table, one table handles the whole
  hierarchy (Electronics > Chargers > iPhone, or Electronics > Cables > TypeC > TypeC‑to‑TypeC),
  and each node can carry its own `image_url`.
- `marques`: brand name + logo, referenced by products.
- `products`: references `category_id`, `type1_id` (required), `type2_id`/`type3_id` (optional),
  `marque_id`, price, stock, image.
- `achats` + `achat_items`: one achat (sale) has many items, each with quantity and a snapshotted
  unit price. Postgres triggers auto-update `achats.total_price` and decrement `products.stock`
  whenever items change — the app never has to calculate totals by hand.
- Three views (`v_daily_revenue`, `v_top_products`, `v_revenue_by_category`) power the Analyse tab
  directly from SQL, no client-side aggregation needed.

## Setup steps
1. Create a Supabase project.
2. SQL editor → paste and run `sql/schema.sql`.
3. Storage → follow `sql/STORAGE_SETUP.md` to create the `shop-images` bucket and its policies.
4. Create your first admin user: sign them up via Supabase Auth, then in the SQL editor:
   ```sql
   insert into profiles (id, role) values ('<user-uuid-from-auth-users>', 'admin');
   ```
5. In `flutter_app/lib/main.dart`, replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY`
   with your project's values (Project Settings → API).
6. `cd flutter_app && flutter pub get && flutter run`.

## App structure
- `lib/screens/home_shell.dart` — bottom navigation shell (Products / Achats / Analyse).
- `lib/screens/products/` — product list with category/type filters, add/edit form with
  cascading dropdowns (category → type1 → type2 → type3 → marque) and image picker, plus
  `catalog_screen.dart` to manage categories/types/marques themselves (reachable via the icon
  in the Products app bar).
- `lib/screens/achats/` — achat list, and a form to build a cart (search products, tap + / − to
  set quantity) with a live-updating total, matching your "choose products, choose quantity,
  total appears" requirement.
- `lib/screens/analyse/` — daily revenue line chart, top-5 products bar list, revenue-by-category
  pie chart, plus two KPI cards (total revenue, total number of sales).
- `lib/theme/app_theme.dart` — gold (#C9A227) / black / white palette, used consistently across
  app bar, buttons, nav bar, and cards.

## Notes / things you'll likely want to extend
- Authentication screens aren't included (login/signup) — currently the app assumes a signed-in
  session. Add a simple email/password sign-in screen in front of `HomeShell` when you build the
  worker-facing app, and gate admin-only actions (delete, catalog management) behind
  `profiles.role == 'admin'`.
- The worker-side app can reuse the same models/services; just hide the catalog-management and
  analytics screens and keep Achats (recording sales) + read-only Products.
- `unitPrice` is snapshotted into `achat_items` at sale time, so changing a product's price later
  won't rewrite historical sales — that's intentional for accurate analysis.
