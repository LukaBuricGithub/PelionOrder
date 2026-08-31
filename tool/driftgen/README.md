# driftgen — isolated drift codegen helper

This throwaway package exists **only** to generate
`../../lib/features/database/app_database.g.dart`.

## Why it exists

On this toolchain (Dart 3.10), running `dart run build_runner build` inside the
main app fails with:

> 'dart compile' does not support build hooks, use 'dart build' instead.

The main app's dependency graph contains native-asset build hooks
(`sqlite3` ≥ 3.0.0, and `objective_c` via `path_provider_foundation`), which
break build_runner's entrypoint compilation. `flutter build` / `flutter run`
are unaffected — only build_runner is.

This package sidesteps that by depending on **only** `flutter` + `drift` +
`drift_dev` + `build_runner` (no `path_provider`, so no `objective_c`) and
pinning a **hook-free `sqlite3` (2.9.4)** via `dependency_overrides`. It only
needs to resolve/analyze; it never runs, so the old sqlite3 API is fine.

## How to regenerate

1. Keep the copies in `lib/` in sync with the real project:
   - `lib/tables.dart`      ← `lib/features/database/tables.dart`
   - `lib/converters.dart`  ← `lib/features/database/converters.dart` (import
     path adjusted to `order_item.dart`)
   - `lib/order_item.dart`  ← `lib/features/cashregister/models/order_item.dart`
   - `lib/app_database.dart` ← same `@DriftDatabase` class + DAO methods as the
     real one, but with the `_openConnection` / `path_provider` connection code
     stripped (drift does not generate from it).
2. From this directory:
   ```
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```
3. Copy the result back:
   ```
   cp lib/app_database.g.dart ../../lib/features/database/app_database.g.dart
   ```

The generated file is a `part of 'app_database.dart'` and is portable because
it reflects only the tables, converters and DAO method signatures — all of which
are identical between the two `app_database.dart` files.
