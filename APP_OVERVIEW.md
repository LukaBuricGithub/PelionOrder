# Orderman — Application Overview

**Orderman** is a Flutter rewrite of the `pelion-kasa-dev` Kotlin/Android app: a
restaurant **point-of-sale & waiter-ordering** application for Android and iOS.
It follows the architecture and conventions of the **ikasa** Flutter app while
implementing the feature set of the original Kotlin app.

- **App id:** `hr.pelion.orderman` · **Display name:** Pelion Order
  (the Dart package / project folder remain `orderman`)
- **Dart package:** `orderman`
- **Backend:** each venue's own **on-premise server** on the local network. The
  selected server profile's address is used as the URL host and its access key
  is sent in the `X-API-KEY` header. Cleartext HTTP (local network).
- **Locale:** Croatian (`hr_HR`), EUR, portrait-only.

---

## Architecture (mirrors ikasa)

Feature-based, "clean-ish" layering. State via **Riverpod 2.x** (manual
providers, no codegen). Routing via **GoRouter** with a redirect auth gate.
Networking over **`package:http`** with a shared retry helper. Local persistence
via **drift** (SQLite). Models are plain Dart with manual `fromJson` — no
freezed / json_serializable.

```
lib/
├── main.dart                     # entry: ProviderScope + MaterialApp.router, hr_HR
├── app/
│   ├── app_config.dart           # venue scheme / api prefix / timeouts / heartbeat
│   ├── app_theme.dart            # Material 3 light+dark, Inter font (ported from ikasa)
│   └── router.dart               # GoRouter + redirect auth gate
└── features/
    ├── shared/                   # cross-cutting
    │   ├── data/                 # api_exception, retrying_http, venue_api_client
    │   ├── presentation/         # online_status_badge (+ more to come)
    │   ├── services/             # connectivity_service
    │   ├── state/                # shared_preferences_provider, venue_api_client_provider
    │   └── util/                 # croatian_bool ("D"/"N")
    ├── database/                 # drift: tables.dart, converters.dart, app_database(.g).dart
    ├── master_data/              # users/tables/terraces/groups/articles/remarks/branches
    │   ├── models/               # domain models (UPPERCASE remote-key mapping)
    │   ├── data/                 # master_data_api, master_data_repository (sync + cache)
    │   └── state/                # api/repository/heartbeat providers
    ├── profiles/                 # server profiles (ApiEntry) — SharedPreferences
    ├── settings/                 # table view size, group-articles toggle, business name
    ├── auth/                     # login / PIN / session (current user)
    ├── cashregister/             # ordering (models + order_request done; screens WIP)
    └── traffic/                  # reporting (WIP)
```

Per-feature layering: `data/` (APIs, repositories, storage), `models/`,
`state/` (Riverpod providers/controllers), `presentation/` (screens/widgets).

---

## What is implemented (this pass)

**Foundation (all cross-cutting pieces):**
- Domain models for every entity, mapping the venue server's UPPERCASE Croatian
  JSON keys and `"D"/"N"` booleans.
- drift database with the full schema (master-data cache + offline order queue)
  and DAO methods. Order lifecycle encoded by `pending`/`sent` flags.
- Shared HTTP layer: `VenueApiClient` (host injection + `X-API-KEY`),
  `retrying_http`, typed `ApiException` / `NoConnectionException`.
- `MasterDataApi` (all master-data + ping endpoints) and
  `MasterDataRepository` (delete-all-then-insert sync, offline-first cache
  fallback, Db↔domain mapping).
- **Critical:** `OrderRequest.toJsonString` reproduces the reference client's
  hand-built, non-standard `postOrder` body byte-for-byte (unquoted `userCode`,
  bare nested item objects, joined-string remarks, grouping toggle).
- Online/offline **heartbeat** (`HeartbeatController`, 10s/30s).
- Server **profiles** CRUD + selection; **settings** (table view size,
  group-articles toggle, business name).

**Login area (fully functional):**
- Splash → Login → PIN → Cash Register → logout loop.
- Login screen: single read-only profile, online status, auto/manual
  master-data sync, PIN entry gated on cached data.
- PIN screen: numeric keypad validating against cached users (works offline).
- Settings screen: single server profile (add/edit/delete), table-tile size,
  grouping toggle.

**Cash register / ordering area (fully functional):**
- Cash Register home: user, online status, pending-orders badge, menu, and
  **heartbeat-driven auto-resend** of the offline queue.
- Table Select: terrace chips + colour-coded table grid (free / yours / other /
  not-sent), tile size from settings, reservation on open (optimistic offline),
  30s refresh, permission gating (`allTablesOpenRight`).
- New Order: group chips + name search, +/- quantities with live running total,
  Details / Send; Back saves the draft (keeps the table) or discards it and
  releases the reservation.
- Order Details: per-line quantity (± and exact-value dialog), predefined +
  custom remarks, delete and drag-to-reorder, Send — quantity/delete gated by
  `changeQuantityRight` / `deleteRight`.
- Tables Overview (read-only occupied tables by zone) and Table Details
  (read-only server bill via `tableDetail`).
- Orders list (the pending/unsent queue) → open details.
- `OrderRepository`: order lifecycle (`pending`/`sent`), send/queue,
  `sendPendingOrders`, and optimistic-offline reservations.

---

## Roadmap (next passes)

1. **Traffic / reporting** (superusers) — reports menu with date-range + branch
   filters; daily/monthly turnover, item, order, stock, delivery, invoice list,
   invoice detail (storno/print), sales by user/payment.
2. Polish — app launcher icons (`flutter_launcher_icons`), shared widgets,
   optional Firebase Crashlytics (currently omitted).

---

## Regenerating drift code (important gotcha)

`dart run build_runner build` **fails on this toolchain** (Dart 3.10): the
package graph contains native-asset build hooks (`sqlite3` ≥ 3.0.0 and
`objective_c` via `path_provider_foundation`), which break build_runner's
entrypoint compilation with:

> 'dart compile' does not support build hooks, use 'dart build' instead.

`flutter build` / `flutter run` are unaffected — only build_runner is. To
regenerate `lib/features/database/app_database.g.dart`, use the isolated
throwaway package that excludes the plugin deps and pins a hook-free `sqlite3`:

- Package: `tool/driftgen/` (see its `README.md`). Pins `sqlite3: 2.9.4` via
  `dependency_overrides`; contains copies of `tables.dart`, `converters.dart`,
  `order_item.dart`, and a connection-stripped `app_database.dart`.
- Run `dart run build_runner build` there, then copy the generated
  `app_database.g.dart` back into `lib/features/database/`.

If the drift tables or DAO method signatures change, update the copies in the
throwaway package to match and regenerate.
