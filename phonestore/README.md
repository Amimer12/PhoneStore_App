# Shop Admin — Mobile App + Web Dashboard

A point-of-sale and back-office system for a small boutique selling **electronics, phone accessories, perfumes, mobile top-ups (Flexy) and phone repairs**. It has two front-ends on one **Supabase** backend:

| Part | Stack | Purpose |
|---|---|---|
| **Mobile app** | Flutter (Material 3) | Daily use: browse stock, record sales, log expenses, view analytics, manage catalog and worker permissions |
| **Web dashboard** | _(fill in: framework / host)_ | Reads the same database for reporting and administration |
| **Backend** | Supabase (Postgres, Auth, Storage, Edge Functions) | Data, row-level security, analytics views, password-reset flow |

> **Note on scope.** This README was written from the app's `lib/` source and from the project's Claude conversation log. The dashboard's own source code was not included. Sections that depend on it are marked **`TODO`**.

---

## Contents

1. [Features](#features)
2. [Architecture](#architecture)
3. [Project structure](#project-structure)
4. [Roles and permissions](#roles-and-permissions)
5. [Authentication](#authentication)
6. [Catalog model: category modes](#catalog-model-category-modes)
7. [Performance: chunking and caching](#performance-chunking-and-caching)
8. [Analytics](#analytics)
9. [Database reference](#database-reference)
10. [Setup](#setup)
11. [Database maintenance and free-tier limits](#database-maintenance-and-free-tier-limits)
12. [Web dashboard](#web-dashboard)
13. [Roadmap and known gaps](#roadmap-and-known-gaps)

---

## Features

**Produits (always visible to every user)**
- Paged product list (20 per page) with a **Voir plus** button.
- Filter by category, type and sub-type. Sort by default (newest), price or stock, ascending or descending. The sort runs server-side, so every page stays in the correct order.
- Low-stock highlighting: under 2 units, or under 200 ml for perfumes.
- Tapping a product loads its full record once. The cost price and margin appear only there.

**Ventes (always visible to every user)**
- Shows the **last 3 days** of sales, plus **one more day per "Voir plus"** tap.
- A sale holds several line items. Totals and stock are maintained by Postgres triggers.
- Sale date and time come from the device clock, not the server's UTC clock. This keeps evening sales on the right calendar day in the daily chart.

**Dépenses**: add, edit and delete expenses, with a daily-totals view.

**Analyse**: KPIs, an hourly chart for today, daily revenue (daily or cumulative), top products and top repairs (by quantity or by profit), and revenue by category.

**Catalogue**: manage categories, a two-level type tree and brands. Types and products can carry an optional image, compressed on-device (quality 50, max width 240 px) to save storage.

**Permissions (admin only)**: a switchboard that controls what the worker role can do.

---

## Architecture

```
┌────────────────────┐        ┌────────────────────┐
│  Flutter app       │        │  Web dashboard     │
│  (admin + worker)  │        │                    │
└─────────┬──────────┘        └─────────┬──────────┘
          │  supabase_flutter / JS      │
          └──────────────┬──────────────┘
                         ▼
        ┌──────────────────────────────────────┐
        │               Supabase               │
        │  Auth (anonymous sessions)           │
        │  Postgres + RLS + triggers           │
        │  Matviews + RPC (analytics)          │
        │  Storage bucket: shop-images         │
        │  Edge Functions: password reset      │
        └──────────────────────────────────────┘
```

All Supabase access in the app goes through three services in `lib/services/`. Screens never talk to Supabase directly.

---

## Project structure

```
lib/
├── main.dart                     # loads .env, initialises Supabase, runs the app
├── models/
│   ├── achat.dart                # Achat (sale) + AchatItem
│   ├── category.dart             # Category + CategoryMode
│   ├── depense.dart
│   ├── marque.dart               # brand; MarqueType tech | perfum
│   ├── product.dart
│   ├── product_type.dart         # 2-level type tree
│   └── worker_permissions.dart   # 5 sections × actions
├── services/
│   ├── auth_service.dart         # session, role, admin login/reset
│   ├── permissions_service.dart  # canX getters + shared notifier
│   ├── query_cache.dart          # generic cache with in-flight de-duplication
│   └── supabase_service.dart     # every table, RPC, view and storage call
├── screens/
│   ├── auth_gate.dart            # swaps screens when the role changes
│   ├── home_shell.dart           # bottom navigation (built from permissions)
│   ├── login_screen.dart
│   ├── auth/                     # role choice, admin login, admin reset
│   ├── products/                 # list, form, catalog management
│   ├── achats/                   # sales list and sale form
│   ├── depenses/
│   ├── analyse/
│   └── permissions/              # admin-only permissions tab
├── theme/                        # gold / black / white theme, category icons
└── widgets/                      # app logo, selector chips
```

About 7,800 lines of Dart across 31 files. Dependencies: `supabase_flutter`, `flutter_dotenv`, `fl_chart`, `image_picker`, `google_fonts`, `intl`.

---

## Roles and permissions

There are two roles, **admin** and **worker**. The admin is never restricted. The worker is controlled by a single, shop-wide row in `worker_permissions`. There are no per-worker permission sets.

| Section | View | Add | Modify | Delete | Notes |
|---|:-:|:-:|:-:|:-:|---|
| **Catalogue** (categories, types, brands) | ✅ toggle | ✅ | ✅ | ✅ | One set of flags covers all catalog tables |
| **Produits** | 🔒 always on | ✅ | ✅ | ✅ | |
| **Ventes** (`achats`) | 🔒 always on | ✅ | ✅ | ✅ | |
| **Dépenses** | ✅ toggle | ✅ | ✅ | ✅ | |
| **Analyse** | ✅ toggle | — | — | — | View-only section |

**One fixed rule:** a worker can always see products and sales. Every other permission can be changed.

Defaults match how the app behaved before permissions existed:

| Section | Worker default |
|---|---|
| Catalogue | no access |
| Produits | read-only |
| Ventes | full access |
| Dépenses | full access |
| Analyse | hidden |

**How it is enforced**
- The bottom navigation bar is built from the loaded permissions. Dépenses and Analyse tabs appear only when allowed, and the **Permissions** tab is admin-only.
- The permissions row is loaded at start-up, before the first frame, and reloaded when the admin saves, so open screens update without a restart.
- `PermissionsService.canX` getters short-circuit to `true` for the admin.
- **Server side:** UI gating is not security. Row-level security on the tables must mirror these flags. See the [Database reference](#database-reference).

---

## Authentication

The app uses **no email/password accounts**. Each device gets a **Supabase anonymous session** and then claims a role.

1. **Worker**: calls the `claim_worker()` RPC. No secret is needed.
2. **Admin**: calls `claim_admin(p_password)`. The password is checked **inside the same server call** that grants the role, so there is no gap between verification and grant.
3. The role is stored in `profiles.role`. On launch, `AuthService.bootstrap()` resumes the saved session and reads the role. If a session exists but has no profile row, the device is signed out.
4. **Forgot admin password** (two Edge Functions):
   - `admin-request-reset` generates a 6-digit code and sends it by **WhatsApp** to the shop's fixed admin number. The app never sees the number or the code.
   - `admin-confirm-reset` verifies the code, sets the new password atomically, and logs the device in as admin.

`AuthGate` listens to `AuthService.roleNotifier`, so signing in, out or switching role swaps the screen automatically.

---

## Catalog model: category modes

Each category has a **mode** that changes how its products and sales behave:

| Mode | Example | Behaviour |
|---|---|---|
| `hierarchical` | Electronics | type1 + optional type2, fixed price per product |
| `simple` | Flexy (top-up) | type1 only, no fixed price, typed in at sale time |
| `perfume` | Perfum | type1 = perfume name, type2 = size; fixed price per combination; stock in litres |
| `repair` | Réparation | no products; the worker picks one or more repair types and enters one total price for the combo |

Brands (`marques`) are split into `tech` and `perfum`. Perfume categories can only pick perfum brands, and everything else can only pick tech brands. Types and brands can turn on a **low-stock alert**.

---

## Performance: chunking and caching

The app minimises Supabase reads.

- **Products are paged server-side** (`.range`, 20 per page). The query asks for 21 rows, so the extra row tells the app whether another page exists without a separate count query.
- **Two projections.** The list fetches only what a card shows. It leaves out cost price. The full row loads once, on tap.
- **Only the selected category's products are fetched.**
- **Sales are paged by day.** The `get_achat_dates` RPC returns distinct dates. Then only those days' sales are fetched. A day with 40 sales costs the same as a day with one.
- **`QueryCache<T>`** keeps results until invalidated. It also **de-duplicates in-flight requests**: a second caller asking for the same key gets the same `Future`.
- **Reference data is cached** for the session: categories, brands and types. It is re-fetched only after a write.
- **Invalidation:** any product write clears all product caches. Any sale write clears all sales caches.

---

## Analytics

All analytics are precomputed in Postgres and read through RPCs and materialized views:

| Object | Used for |
|---|---|
| `get_analytics_kpis(date)` | KPI tiles (`security invoker`) |
| `get_hourly_achats(date)` | hourly chart for today (`security invoker`) |
| `mv_daily_revenue` | daily / cumulative revenue |
| `mv_top_products`, `mv_top_repairs` | rankings (`RANK()` by quantity and by profit) |
| `mv_revenue_by_category` | per-category revenue (+ a total row) |
| `v_daily_depenses` | daily expense totals |
| `refresh_analytics()` | refreshes the matviews (`security definer`) |

Matviews are refreshed **only** by the refresh button on the Analyse screen, not on every write.

**Moving off the anonymous phase.** Analytics grants start with the `anon` role. Once real Supabase Auth is wired up, run the companion SQL. It revokes `anon` and grants `authenticated` on the three functions, the four matviews and `v_daily_depenses`. Row-level security on `achats`, `products` and the other tables is handled separately.

---

## Database reference

The Postgres tables and functions the app code touches:

| Table | Purpose |
|---|---|
| `categories` | name, `icon_key`, `mode` |
| `product_types` | type tree (`level`, `parent_id`, optional image, `volume_liters`, `prix`, `stock_alert_activated`) |
| `marques` | brands, with `type` tech or perfum |
| `products` | reference, name, category, type1, type2, brand, `prix`, `prix_achat` (cost), `stock`, `image_url` |
| `achats` | a sale: `achat_date`, `achat_time`, totals (price, cost, profit) |
| `achat_items` | sale lines: product, quantity, unit price, unit cost, type2, category, label |
| `achat_item_types` | links repair lines to their selected types |
| `depenses` | expenses: name, price, date |
| `profiles` | `id` (the auth user) → `role` |
| `worker_permissions` | the single row (`id = 1`) with all permission flags |

| RPC / function | Purpose |
|---|---|
| `claim_worker()`, `claim_admin(p_password)` | role assignment |
| `get_achat_dates(p_limit, p_offset)` | distinct sale dates, newest first |
| `get_analytics_kpis`, `get_hourly_achats`, `refresh_analytics` | analytics |

Postgres triggers keep `achats` totals and product stock in sync when sale lines change.

**Storage:** the public bucket `shop-images` holds `product-types/` and `products/` images.

> **`TODO`**: add the full schema file (`schema.sql`) and the migration files to the repo, and link them here.

---

## Setup

### Prerequisites
- Flutter SDK (Dart 3, Material 3)
- A Supabase project

### 1. Backend
1. Create a Supabase project.
2. Run the schema and migrations in the SQL editor: schema, then the permissions migration (`worker_permissions`, `profiles`, `claim_*`, `get_achat_dates`), then the analytics rewrite.
3. Enable **Anonymous sign-ins** in Authentication → Providers.
4. Create the public Storage bucket **`shop-images`**.
5. Deploy the Edge Functions `admin-request-reset` and `admin-confirm-reset`, and set their secrets (WhatsApp provider credentials and the admin number).

### 2. Mobile app
Create a `.env` file at the project root and register it under `flutter: assets:` in `pubspec.yaml`:

```env
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
```

Use the **anon** key only. Never put the service-role key in a mobile app.

```bash
flutter pub get
flutter run
```

If the logo asset is used, declare it under `flutter: assets:` as well (see `widgets/app_logo.dart`).

### 3. First launch
1. Open the app and choose **Administrateur**. Set or enter the admin password.
2. Create categories, types and brands in **Catalogue**.
3. Open the **Permissions** tab and configure what workers may do.

---

## Database maintenance and free-tier limits

The Supabase free tier gives 500 MB of database storage. Sales history is the main source of growth. This estimate comes from the project conversation. It is a rough model that assumes about 250 bytes per sale line and about 150 bytes per sale, indexes included:

| Sale lines / month | Growth / year | Years until a ~450 MB headroom is full |
|---:|---:|---:|
| 500 | ~2 MB | ~214 |
| 2,000 | ~8 MB | ~54 |
| 10,000 | ~42 MB | ~11 |
| 20,000 | ~84 MB | ~5 |

**Conclusion:** at normal boutique volumes, **a monthly archive is not required for storage**. Images are the real risk, which is why they are compressed on-device before upload.

The conversation also covers an **optional monthly archive pipeline**. It uses Google Drive with a `drive.file` scope, set up through the OAuth Playground with a **Web application** OAuth client. It needs the exact redirect URI `https://developers.google.com/oauthplayground`.

> **`TODO`**: document the archive pipeline's actual implementation here (function name, schedule, archive format, restore procedure). Its code was not part of the files provided.

---

## Web dashboard

> **`TODO`**: this section needs the dashboard source. Suggested content:
> - Stack and hosting
> - Environment variables (`SUPABASE_URL`, key used)
> - Pages and what each one reads
> - How it signs in, and which Supabase role it uses
> - Local run and deploy commands

The dashboard reads the same Supabase database. Any new table or view it needs should follow the same rule as the app: grant access to `authenticated` only, with RLS on.

---

## Roadmap and known gaps

- **Real accounts.** Today any device can claim the worker role without a secret. Anonymous sessions plus RLS are a pragmatic shortcut for a single shop. Moving to real per-user accounts would also allow per-worker permissions.
- **Permissions are enforced mainly in the UI.** Confirm that RLS policies mirror each `worker_permissions` flag, especially deletes and `prix_achat` reads. If a worker can query `products` directly, cost price is exposed.
- **`main.dart` cleanup.** A variable is named `supabaseServiceKey` but holds the anon key. Rename it to avoid confusion.
- **Matview freshness.** Analytics update only when the refresh button is pressed. A scheduled refresh (`pg_cron`) would remove that manual step.
- **Language.** The UI is in French and the code and comments are in English.

---

## License

_Add a license, or mark the project private._