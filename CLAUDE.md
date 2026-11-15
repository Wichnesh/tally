# Tally: AI context

The app is called **Tally**. It was earlier called "Ghee Tally".

Desktop app (macOS, Windows) for a ghee / dairy business ("Amutham, From the Nature"). It records daily sales and customer payments, tracks each customer's balance, and keeps a cash book of the shop's money and expenses. Everything runs offline; there is no server.

`README.md` is the user manual: what every screen does and how to use it. This file is for whoever changes the code.

## The person using this

- The owner is not a developer. Requests are short and informal (e.g. "cache" means cash, "EB" is the electricity bill).
- Explain things in plain words and keep the app simple.
- Money is Indian rupees in Indian grouping (₹1,00,000). Quantities are kg.
- **Update `README.md` with every feature change.** The user asked for it to stay complete.

## Run, test, analyze

Flutter **3.41.4** through fvm. The `fvm` shell alias may not exist in a non-interactive shell, so use the full path:

```bash
F=~/fvm/versions/3.41.4/bin
$F/dart analyze lib test                 # must report "No issues found!"
$F/flutter test --timeout 180s           # all tests must pass
$F/flutter run -d macos                  # run the app
SHOT_DIR=/tmp/shots $F/flutter test test/ui_smoke_test.dart   # screenshots of every screen
$F/dart run flutter_launcher_icons       # rebuild app icons from assets/app_icon.png
```

- `flutter analyze` **crashes** in this folder because the parent folder name has a space. Use `dart analyze`.
- To install into `/Applications`, do a clean build (`rm -rf build/macos`, then `flutter build macos`). A partial rebuild can leave the outer app's signature stale: `codesign --verify --deep --strict` reports "nested code is modified or invalid" for `App.framework`. Check the signature before copying the app.
- `flutter run` / `open build/.../Tally.app` uses the **user's real data** (see "Data and storage"). Tests use temporary folders.
- **Windows installer:** every push to `main` runs `.github/workflows/windows.yml` on a GitHub Windows machine. It runs the tests (a failure only gives a warning), runs `flutter build windows`, copies the VC++ runtime DLLs next to `Tally.exe`, and builds `installer/tally.iss` (Inno Setup, per-user install, never change its `AppId`). The download it produces is `Tally-Windows`, holding `Tally-Setup.exe` and `Tally-portable/`. Fetch it with `gh run download -R Wichnesh/tally -n Tally-Windows`.
- **Windows** builds only on Windows (a Windows PC with Visual Studio 2022 and Desktop C++, or the GitHub workflow above). As of 2026-11-15 the Windows app has **never been built or run**. The window minimum size (`WM_GETMINMAXINFO` in `windows/runner/win32_window.cpp`, 1100×720 like macOS) was written on a Mac and not compiled. The first Windows build should confirm it, along with the AppData data folder and backups to `Documents\Tally Backups`.
- After UI changes, run `test/ui_smoke_test.dart` with `SHOT_DIR` and look at the PNGs. It renders every screen and dialog at 1100×720 (the minimum window size), 1084×680 (the content area left inside a minimum-size window on Windows / macOS) and 1440×900, and fails on any overflow.

## Stack

GetX (state, navigation, dialogs, snackbars) · get_storage (local JSON file) · intl · excel · cryptography (AES-GCM, PBKDF2) · file_picker · url_launcher · path_provider. The app icons come from flutter_launcher_icons.

## Code map

```
lib/
  main.dart                    init storage, Get.put controllers, start on StartupPage
  models.dart                  Customer, Entry, Change, HistoryItem, CashTxn (+ JSON)
  utils.dart                   money/moneyExact/perKg/kg/dates, priceFromFormula, PayStatus colours
  data/indian_states.dart      28 states + 8 UTs
  controllers/
    tally_controller.dart      ALL data + business logic + saving (single source of truth)
    customer_filter.dart       Customer / State / District filter (one instance per screen)
    dashboard_controller.dart  dashboard filters (period, customers, products, modes)
    nav_controller.dart        Tabs indices, selected day/week/month, calendar & customers filters,
                               calendarCash (Daily/Weekly/Monthly "Sales | Cash book" switch)
  services/
    app_data.dart              appDataDir (macOS: Documents in the sandbox; Windows: AppData\Roaming\com.gheetally\Tally), copyOldWindowsData
    backup_service.dart        encrypted auto backups, restore, password
    cashbook.dart              pure: per account per day opening / in / out / closing; cashTotals for a period
    excel_export.dart          7-sheet .xlsx
    stats.dart                 pure: entriesInRange, productStats, modeStats
  pages/   startup, home (NavigationRail), dashboard, daily, weekly, monthly, cashbook,
           customers, customer_detail, history, backup (Export & Backup), settings
  widgets/ entry_dialog, cash_dialog, cash_views (CashDayView, CashPeriodView, CashAddButtons,
           SalesCashSwitch), customer_dialog, customer_filter_bar (CustomerPicker + search
           window), history_view, price_history, proof_tile, restore_flow, common
test/      backup_test (controller + backups + Excel), app_data_test, cashbook_test, customer_filter_test,
           stats_test, widget_test (utils), ui_smoke_test (all screens + user flows)
assets/    logo.png (round, transparent), app_icon.png (1024 icon source)
```

## Data model and business rules

**Customer:** `code` (unique, auto 1001, 1002…; names may repeat), name, phone, `location` (shown as "Area / Town"), `district` (free text), `state` (from `indianStates`, '' = not set), proofs (copied into the app's `proofs/` folder), and old-book figures `openingBought`, `openingPaid`, `openingDate`.
- `label` = "Name · #code". `place` = area, district, state.
- Old-book figures **count in** the customer's totals: `soldOf`, `paidOf`, `balanceOf`, paid %, colour, Dashboard "All time", the Excel all-time balance.
- They **do not count in** any period's sales or money received, or in the cash book.

**Entry:** one line per customer per sale and/or payment: `qty` (kg), `rate` (= price per kg), optional `percent` + `baseRate`, `paid`, `paymentMode` (only kept when paid > 0), product, note. `amount = qty × rate`.
- **Price formula:** `rate = percent × baseRate ÷ priceDivisor` (default 1326, set in Settings), rounded to the paisa (`priceFromFormula`).
- The entry form opens in formula mode unless the product is in `manualPriceProducts` (its last sale had a typed price).
- A payment with no sale is an Entry with `qty: 0`. Cash book → "Customer payment" saves one through `saveEntry`.

**Status colour:** paid % = paid ÷ bought (all time, including the old book). Red below `redBelow` (40), green from `greenFrom` (75), yellow in between.

**Change history (audit):** editing or deleting an entry, customer or cash-book line **requires a reason**. It is logged as a `HistoryItem` with old → new values for each field (`entryFields`, `customerFields`, `cashFields` + `diff`). Adding something new is not logged. If nothing changed, the form just closes and asks for no reason. Keep this rule for anything new that can be edited.

**Cash book:** accounts (default Cash, Bank). `CashTxn` types: `expense`, `income` (other money in), `transfer`, `opening` (balance counted when the shop opened).
- Customer payments go into an account by payment mode (`accountForMode`: the `modeAccounts` mapping in Settings; otherwise "cash" → the cash account, any other mode → the first non-cash account).
- Each day per account: opening (counted, else the previous closing) + in − out = closing. A counted opening shows short / extra against the expected opening.
- Expenses are shop-wide: they are hidden from the Dashboard and Excel when a customer / state / district filter is active.
- The cash book views are in `widgets/cash_views.dart`. The Cash book screen uses them, and so do Daily / Weekly / Monthly when `nav.calendarCash` is on (the "Sales | Cash book" switch, shared by the three). In that mode the customer filter bar is hidden, because the cash book is shop-wide, and a day click opens Daily (`nav.openDay`). The switch has no icons so that it fits next to Weekly's Calendar / Table switch at 1100 px.

**Filters:** `CustomerFilter`: null = All, '' = "Not set". District matching ignores case and spaces.
- Daily / Weekly / Monthly share `nav.calendarFilter`. The Dashboard filter also applies to its All-time section.
- Picking a state or district clears a chosen customer who is not in it.

## Data and storage (do not break)

- **Old names kept on purpose:** the shown name is "Tally" (UI text, macOS `PRODUCT_NAME`, Windows `BINARY_NAME`, backup folder `Tally Backups`). Keep these old names:
  - the bundle ID `com.gheetally.gheeTally`, which decides where the macOS app data lives. Renaming it loses the data.
  - the Dart package `ghee_tally`, which is used only inside the code.

- **App data:** get_storage file `GetStorage.gs` plus a `proofs/` folder in `appDataDir()`. On macOS that is `~/Library/Containers/com.gheetally.gheeTally/Data/Documents/` (the sandbox; `GetStorage.init()`). On Windows it is `%APPDATA%\com.gheetally\Tally\`, opened in `main.dart` with `GetStorage('GetStorage', dir)`, because the shared Documents folder holds other apps' files and is often synced by OneDrive. `copyOldWindowsData` copies an earlier build's `Documents\GetStorage.gs` (only if it has customers / entries) and its proofs once, and deletes nothing. The very early Mac in-app `backups` folder move runs only on macOS and only for `.gtb` files: on Windows that path is the user's own `Documents\backups`. Keys: customers, entries, products, paymentModes, history, accounts, modeAccounts, expenseCategories, incomeSources, cashTxns, redBelow, greenFrom, priceDivisor, manualPriceProducts, lastState, backupSalt, backupKey, lastBackup.
- **Backups:** `~/Documents/Tally Backups/`, outside the app. It is allowed by the sandbox entitlement `temporary-exception.files.home-relative-path.read-write` in both `macos/Runner/*.entitlements`. That entitlement also lists the old `~/Documents/Ghee Tally Backups/`, and it must stay: on startup `_moveOldBackups` → `BackupService.moveFolder` moves that folder into the new one. The move renames the whole folder, or merges file by file keeping the newer copy and each file's modified time. `refreshList` and `_backup` await the move (`_moving`).
  - A few seconds after every change (`TallyController.changes` → `ever`), `daily_YYYY-MM-DD.gtb` is updated in place. Manual backups are `manual_*.gtb`.
  - Photos are encrypted once into `proofs/<keyId>/`.
  - Format: `"GTB1"` | salt 16 | nonce 12 | mac 16 | AES-256-GCM(gzip(JSON)). The key is PBKDF2-SHA256 with 100k rounds.
  - **Never auto-backup when the app has no data** (`hasData`), so an empty or damaged app cannot overwrite good backups.
  - On startup, empty or unreadable data plus existing backups → the restore offer (`checkForRecovery`, run by StartupPage).
- **Backward compatibility:** every `fromJson` must accept data saved by older versions (missing keys → defaults). Never rename or remove stored keys. When adding data, also add it to `exportData` / `importData` so backups include it.
- **Renaming a product:** changing `defaultProducts` only affects new installs, because the saved `products` list wins. Add the old → new name to `TallyController.renamedProducts`. On load and on restore, `_renameOldProducts` renames the name in the list, in entries and in `manualPriceProducts`, but only while the list has the old name and not the new one. ("Dust White Ghee" → "Dust".)
- Tests must never touch real data. Use `_FakePaths` (path_provider) and `BackupService.dirOverride`, as the existing tests do.

## GetX and Flutter pitfalls already hit here

- `Obx` only tracks observables read **inside its own builder**. A child widget that reads Rx in its own `build()` needs its own `Obx` (see `_DayView` / `_MonthView` in cashbook_page).
- Read every Rx value a getter depends on with no short-circuit, or the `Obx` misses changes (see `CustomerFilter.isActive` / `inPlace`).
- `DropdownButtonFormField` asserts if its value is not in its items. Keep the current value in the item list (the `_withValue` pattern), and use `key: ValueKey(value)` so the field picks up changes made outside it (`initialValue` is read only once).
- Do not use Flutter `DropdownMenu` with `enableFilter` for picking a customer: its text can disagree with the real selection. Use `CustomerPicker`, a read-only field that opens a search window. On Enter, compute results from the current text.
- Do not change Rx lists or call `_save` during `initState` / `build`.
- Material `Autocomplete` with an external controller does not recompute its options when other state changes. Nudge the controller (`_changeState` in customer_dialog).
- Wide `DataTable`s need horizontal scrolling. The monthly grid scrolls when rows would be < 80 px.

## Conventions

- All business logic lives in `TallyController`; pages stay thin. Pure calculations go in `services/` with unit tests.
- Comments and UI text use plain English for a non-technical user. Use `money()` for amounts and `moneyExact()` / `perKg()` where paise matter.
- Every new screen or dialog gets a step in `ui_smoke_test.dart`. Every rule gets a test.
- Git repository, private on GitHub: `Wichnesh/tally` (branch `main`). On this Mac the active `gh` account is a different one, so push with that account's token: `GH_TOKEN=$(gh auth token --user Wichnesh) git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push`. Commit or push only when asked.
