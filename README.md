# Tally

(Earlier called **Ghee Tally**.)

A simple desktop app for a ghee business. It records how much ghee each customer buys every day, at what price, and how much they pay. It shows who owes money and marks every customer **Red**, **Yellow** or **Green** depending on how much of their purchases they have paid.

Built with **Flutter** (desktop) and **GetX** (state management). Runs fully offline on macOS and Windows.

---

## Logo and app icon

The Amutham logo (`assets/logo.png`) is shown on the **start screen** each time the app opens (about 2 seconds, then the app opens by itself) and at the top of the left menu. The same logo is the **app icon** in the macOS Dock and the Windows taskbar.

To change the icon: replace `assets/app_icon.png` (1024 × 1024, transparent background) and run `fvm dart run flutter_launcher_icons`, then rebuild the app.

## How to run

From this folder:

```bash
fvm flutter pub get          # first time only
fvm flutter run -d macos     # on a Mac
flutter run -d windows       # on a Windows PC
```

To make a finished app you can double-click:

```bash
rm -rf build/macos && fvm flutter build macos   # app: build/macos/Build/Products/Release/Tally.app
flutter build windows        # app: the whole build\windows\x64\runner\Release folder (build on Windows)
```

(Removing `build/macos` first makes a clean build. A partial rebuild can leave the app's signature out of date.)

### On Windows

**Ready-made installer (easiest):** the code is in the private GitHub repository `Wichnesh/tally`. Every push to `main` makes GitHub build the Windows app on a Windows machine (`.github/workflows/windows.yml`). The result is a download called **Tally-Windows** on the run's page (GitHub → Actions → Windows build), which contains:

- **`Tally-Setup.exe`**: copy it to the Windows PC and double-click it. It installs Tally for that Windows user (no administrator password needed), with a Start menu entry and a desktop icon. Running it again with a newer version updates Tally. Uninstalling, from Windows Settings → Apps, removes only the program: the data and backups stay.
- **`Tally-portable`**: the same app as a plain folder, for use without installing.

The installer is not signed. If Windows shows "Windows protected your PC", click **More info → Run anyway**. This can happen when the file came by email or download; it doesn't happen when it is copied from a USB drive.

**Building on a Windows PC yourself:** Flutter can only build the Windows app on Windows (not on a Mac).

1. Install **Flutter 3.41.4** and **Visual Studio 2022** (the free Community edition) with the **Desktop development with C++** option. Run `flutter doctor` to check everything is ready.
2. Copy this project folder to the PC. In it, run `flutter pub get`, then `flutter build windows`.
3. The finished app is the **whole folder** `build\windows\x64\runner\Release`: `Tally.exe` plus its `.dll` files and the `data` folder. `Tally.exe` does not work on its own. Copy the whole folder to a fixed place, for example `C:\Tally`, and make a desktop shortcut to `Tally.exe`.
4. To update later: quit Tally and replace that folder with the new `Release` folder. Your data is not inside it (see "Where the data is saved").

On Windows, as on the Mac, the window cannot be made smaller than 1100 × 720, so every screen fits.

Run the tests (backup encryption, restore, Excel export, customer codes, change history, filters, and every screen's layout) with `fvm flutter test`.

To see screenshots of every screen with sample data (without touching real data):
`SHOT_DIR=/tmp/ghee_shots fvm flutter test test/ui_smoke_test.dart`

> Note: `flutter analyze` crashes in this folder because the parent folder name has a space in it. Use `fvm dart analyze lib test` instead.

---

## How the app works

### Customers
- Each customer has a **customer code** (required, unique), **name** (required), **phone number**, **State**, **District** and **Area / Town**.
- **State:** a dropdown with all 28 states and 8 union territories of India. Optional. A new customer starts with the state you last picked (for a new customer, or when changing a customer's state), so a business that sells mostly in one state rarely has to change it.
- **District:** typed in. As you type, districts already used for that state are suggested (also when your capitals differ), so the same district can be spelt the same way every time. Filters treat "Erode" and "erode" as one district.
- **Area / Town:** street, village or town (optional). This is the old "Location" field; existing values are kept.
- Customers added before State and District existed have them empty until you edit them.
- **From your old book (optional):** for a shop moving from a paper book. Enter the customer's **Total purchases before**, **Total paid before** and the **As on** date; the form shows the **Balance due from old book**. If you only know the balance due, enter it in *Total purchases before* and leave *Total paid before* empty.
  - These amounts are included in the customer's total bought, total paid, balance due, paid % and Red / Yellow / Green colour, the customer list, the Dashboard's **All time** figures, "Balance due" in Add money in, and the Excel Customers sheet (all-time balance, plus *Old book* columns).
  - They are **not** counted as sales or money received on any day, week or month, or in the Cash book, because that money changed hands before the app was used.
  - On the customer's page the history starts with an **Opening (old book)** line, and the running balance continues from it. Changing these amounts needs a reason and is kept in the change history.

**Getting started from a paper book:** add each customer with their old-book figures (As on = the day you start), then set the shop's opening balances in **Cash book → Opening balance** (cash counted, bank balance). From then on, enter sales, payments and expenses as they happen.
- **Customer code:** filled in automatically with the next number (1001, 1002, 1003…). You can type your own code instead, but two customers can never have the same code.
- **Names can repeat.** Two customers can both be called "Ravi Stores"; the code tells them apart. The code is shown next to the name everywhere (e.g. *Ravi Stores · #1001*), including the entry form's customer list and the Excel export.
- Customers added before codes existed were given codes automatically, in the order they were added.
- There is no fixed price on the customer. Prices change often, so the price is entered on each day's entry (see below).
- **Proofs (optional):** press **Upload** in the customer form to attach photos or PDFs (ID card, GST certificate, shop photo). They show on the customer's page; click one to open it. Remove one with the **x** in the form.
- Uploaded proofs are copied into the app's own `proofs` folder, so moving or deleting the original file does not affect them.
- Search on the Customers screen matches code, name, phone, area, district or state.
- **Customers screen filters:** State and District dropdowns (plus Red / Yellow / Green). "Not set" finds customers with no state or district. "Showing X of Y customers" shows how many match.
- Delete a customer from their own page. This also deletes all of their entries. A reason is required (see Change history).

### Entries (sale and payment)
One entry is one line in the tally for one customer on one day. It has:

| Field | Meaning |
|---|---|
| Customer | Who bought or paid. Click the box to open a search window, type part of the name, code, area, district, state or phone (several words narrow it down, e.g. "ravi erode"), then click the customer or press Enter for the first one |
| Date | The day of the sale or payment |
| Product | Chosen from a dropdown: Dust, Yellow Ghee, White Butter, Yellow Butter, Curd, Buttermilk. Press the **+** button next to it to add a new product; it is saved and appears in the list from then on. ("Dust" was earlier called "Dust White Ghee". Saved entries and old backups with the old name are renamed automatically when the app opens or restores them.) |
| Quantity (kg) | How much ghee they bought |
| Percent (%) and Rate (₹) | **Price per kg = Percent × Rate ÷ 1326**, worked out as you type, e.g. *82.5 × ₹8,000 ÷ 1326 = ₹497.74*. Filled in from this customer's last sale of the product. The number 1326 can be changed in **Settings → Price formula** (saved entries keep their price). |
| Price per kg (₹) | Only when you press **Type price per kg instead** (e.g. for products not priced by the formula). The form remembers this per product: a product you last priced by typing opens that way next time; others open with the formula. |
| Amount paid (₹) | Money received |
| Payment mode | **Optional.** How the money was paid: Cash, UPI, Bank transfer. Press the **+** next to it to add another (e.g. Cheque); it stays in the list. Choose **— Not set —** to leave it empty. Only saved when an amount is paid |
| Note | Optional |

- **Sale amount = Quantity × Price per kg** (shown to the paisa, e.g. ₹4,977.40)
- An entry can be a **sale only**, a **payment only**, or **both**.
- Example: Day 1, 200 kg × ₹500 = ₹1,00,000 sold, ₹50,000 paid. Day 2, ₹1,00,000 sold, ₹70,000 paid. The customer has bought ₹2,00,000 and paid ₹1,20,000, so the balance is ₹80,000 and they have paid 60%.

### Price history
Every entry saves the price for that customer, product and day. On a customer's page, switch to **Price history** to see:
- **Current price** of each product for this customer, and the date it started.
- Every sale with its date, product, quantity and price per kg.
- **Change** compared with the previous price of the same product: ▲ ₹20 (went up), ▼ ₹10 (went down), Same, or First price.
- Turn on **Show only price changes** to hide days where the price stayed the same.

To correct a wrong price, edit that entry from the **Entries** view or the Daily screen.

### Dashboard
**Filters** (top of the Dashboard):
- **Period:** Today, This week, This month (default), Last month, All time, or **Choose dates** for any range.
- **Customer / State / District:** all customers, one customer, or everyone in a state and/or district. Click the Customer box to open a search window; once a state or district is chosen, only customers there are listed, and picking a different state clears a customer who is not in it.
- The customer filter applies to the whole Dashboard, including the **All time** section and the customer list. The period applies only to the period figures.
- **Reset filters** goes back to This month, all customers, all products, all modes.

**Totals for the period:** sales, quantity sold, money received, balance for the period, number of entries.

**Sales by product:** one bar per product (Dust, Yellow Ghee, White Butter, Yellow Butter, Curd, Buttermilk, and any added), biggest first. Each shows sales ₹, share %, kg sold, average price per kg and number of sales. Tick product chips to show only those products; the period totals for sales and quantity follow that choice.

**Payments by mode:** one bar per mode (Cash, UPI, Bank transfer, any added, and "Not set" for payments without a mode). Each shows amount received, share % and number of payments. Tick mode chips to show only those modes; the "Received" total follows that choice.

**All time:** total sales, received, outstanding, collected %, Red/Yellow/Green counts, and the customer list. The Customer / State / District filter applies to these (the heading shows it, e.g. "All time · Tamil Nadu"); the period, product and payment-mode filters do not.

### Cash book (shop money, expenses, opening balance)
Left menu → **Cash book**. It tracks the shop's money in each **account** (by default **Cash** and **Bank**; add more in Settings, e.g. a second bank or petty cash).

The cash book can also be opened from **Daily**, **Weekly** and **Monthly**. Use the **Sales | Cash book** switch at the top right of those screens (see Screens).

For each account, each day:

```
Opening  +  Money in  −  Money out  =  Closing
```

- **Opening:** the balance you enter when the shop opens (**Opening balance**, or the ✎ on an account card). If you do not enter one, the day starts from the previous day's closing. When you do enter one, the app shows **Short by ₹…** or **Extra ₹…** compared with what it expected, so missing cash is noticed the same day. The form shows the expected amount with a **Use this** button.
- **Money in:**
  - **Customer payments** from sales entries, added automatically. The payment mode decides the account: Cash → Cash, UPI and Bank transfer → Bank, no mode → Cash. Change this in **Settings → Customer payments go to**.
  - **Add sale entry** (Cash book button), or **Add money in → Sale entry:** opens the full entry form (customer, product, quantity, price per kg, sale amount, amount paid, payment mode), same as Add entry elsewhere. The paid amount appears in the Cash book.
  - **Add money in → Customer payment:** search and pick the customer (their balance due is shown), enter the amount and payment mode; the form shows which account it goes to. It is saved as a customer payment (an entry with no sale), so the customer's balance, paid % and colour, the Daily screen, Dashboard and Cash book all update. It can be edited later like any entry (click it in the Cash book or Daily).
  - **Add money in → Other money in:** owner added money, loan, other income (**+** adds your own source).
- **Money out:** **Add expense**: EB (electricity), rent, salary / wages, milk / raw material, transport / diesel, packing material, repairs, tea / snacks, other (**+** adds your own type). Choose whether it was paid from Cash or Bank.
- **Transfer:** money moved between accounts, e.g. cash deposited in the bank. The total does not change.
- **Edit / delete** any expense, money in, transfer or opening balance; like entries, a reason is required and it is kept in the change history.

**Day view:** a card per account (opening, money in, money out, closing) plus an **All accounts** card, then the lists of money in, expenses, transfers and opening balances for that day. Click a customer payment to open its entry.

**Month view** (and the **week** view on Weekly → Cash book): customer payments, other money in, expenses, net (money in − expenses) and closing balance for the month or week; **Expenses by type** with bars; and a **day-by-day table** (opening, in, out, closing, each account's closing, short / extra). Days after today are not listed. Click a day to open it.

**Dashboard:** for the chosen period it also shows **Expenses** and **Net (received − expenses)** (hidden while a customer / state / district filter is on, because expenses are not linked to customers).

### Change history (edits and deletions)
Every change to existing data is recorded, so you can always see what was changed, when, and why.

- **Editing an entry or customer:** the edit form has a **Reason for change** box. It is **required** whenever something actually changed. If nothing changed, Save just closes the form.
- **Deleting an entry or customer:** the app asks for a **reason for deleting** (required). The deleted values are kept in the history.
- Each record shows the date and time, the customer, each changed field as **old → new**, and the reason.
- Fields tracked for entries: customer, date, product, qty, price/kg, sale, paid, payment mode, note. For customers: code, name, phone, state, district, area / town, proof files.
- Adding new entries and customers is not recorded as a change.

Where to see it:
| Place | What it shows |
|---|---|
| Blue **history** icon next to an entry (Daily table, customer Entries) | Changes to that one entry |
| Customer page → **Change history** | All edits and deletions for that customer and their entries |
| **History** screen (left menu) | Everything, newest first. Search by customer, code or reason; filter Edits / Deletions |
| Excel export → **Change history** sheet | One row per changed field, with old value, new value and reason |

The history is saved with the data and included in backups.

### Red / Yellow / Green status
For every customer:

```
Paid % = Total paid ÷ Total bought × 100
```

| Colour | Default rule | Meaning |
|---|---|---|
| 🔴 Red alert | Paid % below **40%** | Paying too little, follow up |
| 🟡 Watch | Paid % from **40% to 75%** | Keep an eye on them |
| 🟢 Good | Paid % **75% or more** | Paying well |
| ⚪ No sales | Nothing bought yet | — |

Both levels (40% and 75%) are **global** and can be changed with the sliders in **Settings**. Every customer's colour updates immediately.

The percentage uses the customer's **all-time** totals.

### Screens

| Screen | What it shows |
|---|---|
| **Dashboard** | Filters, totals for the chosen period, **Sales by product**, **Payments by mode**, then all-time totals and all customers sorted from worst payer to best (see below) |
| **Daily** | All entries for one day with day totals. Use ◀ ▶ to move day by day, or click the date to pick one. Customer / State / District filter (shared with Weekly and Monthly). **Cash book** (switch at the top right): the day's cash book, the same as Cash book → Day |
| **Weekly** | Monday–Sunday. Switch between two layouts at the top right: **Calendar** shows 7 day columns with each day's totals and entry cards (click a card to edit it, **+** to add an entry on that day, the day name to open it in Daily). **Table** shows one row per customer with sale (black) and paid (green) per day. Same Customer / State / District filter as Daily. **Cash book** (switch at the top right): the week's cash book: totals, expenses by type and a day-by-day table |
| **Monthly** | Month calendar. Each day shows sales, money received, number of entries and kg sold. Days with entries are tinted, today has a coloured border. Click any day to open it in Daily. Month totals at the top. Same Customer / State / District filter as Daily. In a small window the month scrolls instead of squeezing the days. **Cash book** (switch at the top right): the month's cash book, the same as Cash book → Month |
| **Sales \| Cash book switch** | On Daily, Weekly and Monthly. **Sales** shows the screen as described above. **Cash book** shows the shop's money for that day, week or month, with the buttons to add an expense, sale entry, money in, transfer or opening balance. New lines are dated the day shown (on Weekly and Monthly: today, or the first day if today is not in that week or month); the form can change the date. Clicking a day in the week or month table opens that day in Daily. The choice stays when you move between Daily, Weekly and Monthly. The Customer / State / District filter is hidden in Cash book, because the cash book is for the whole shop |
| **Customers** | All customers with search, Red/Yellow/Green filter and State / District filter. Click a customer to open their page |
| **Customer page** | Total bought, total paid, balance due, paid %, and the full history with a running balance. Edit or delete any entry here |
| **History** | Every edit and deletion with old → new values and the reason (see Change history) |
| **Cash book** | Money in each account (Cash, Bank…) day by day: opening balance, money in, expenses, transfers, closing. Day and Month views (see Cash book) |
| **Export & Backup** | Export to Excel, and encrypted backups after every change (see below) |
| **Settings** | Sliders for the Red and Green levels, with a colour preview bar |

### Export to Excel
**Export & Backup → Export to Excel.** Choose a period (This month, Last month, All time, or Choose dates), optionally a customer, state or district (e.g. only Tamil Nadu), press **Export to Excel**, and pick where to save. The file name includes the period and filter. The `.xlsx` file has 7 sheets:

| Sheet | Contents |
|---|---|
| Customers | Code, name, phone, area / town, district, state, bought, paid, balance and paid % for the period, plus all-time balance and status |
| Entries | Every sale and payment: date, code, customer, district, state, product, qty, price/kg, sale, paid, payment mode, note, with a total row |
| Products | Kg sold, sales amount and average price per product |
| Daily | Number of entries, kg, sales and money received per day |
| Change history | Edits and deletions in the period: when, customer, field, old value, new value, reason |
| Cash book | Each day and account: opening, counted?, short / extra, money in, money out, closing |
| Expenses & money in | Every expense, other money in, transfer and opening balance, with totals |

The two cash sheets are shop-wide, so they are left out when the export is limited to some customers.

### Backups (encrypted, kept outside the app)
Data is kept in **two places**:

| | Where | Purpose |
|---|---|---|
| App data | Inside the app's own folder (see "Where the data is saved") | What the app reads and writes |
| Backups | **`Documents/Tally Backups`** in your home folder | Encrypted copies. Outside the app, so uninstalling, updating or damaged app data does not touch them |

**Turn on:** Export & Backup → **Set backup password** (once). After that:
- **A few seconds after every change** (new entry, edit, delete, customer, settings), **today's backup file is updated in place**. No new file is made per change.
- **A new day starts a new file.** So `daily_2026-11-12.gtb` ends up holding that day's final data. The last **60 days** are kept.
- **Daily files hold only the data** (customers, entries, prices, history, settings), so updating them is quick.
- **Proof photos are saved once** into `proofs/<key id>/` inside the backup folder, encrypted. A photo is only written when it is new and is never copied again. Restoring a daily file reads its photos from there.
- When the app opens, a backup is made if today has none yet.
- **Back up now** makes an extra `manual_2026-11-12_143000.gtb` file **with the photos inside**. The last **20** manual files are kept.
- **Automatic backups never run while the app has no data**, so an empty or damaged app can never overwrite good backups.
- Backups are written to a temporary file first and then swapped in, so a crash or power cut never leaves a half-written backup.
- A backup contains everything: customers, entries, products, payment modes, cash book (accounts, expenses, money in, transfers, opening balances), settings, change history and proof files.
- **Save full backup to…** saves one complete file (data + photos) wherever you choose, e.g. a USB drive. Do this now and then, so a copy survives if this computer is lost.
- If you copy a daily file somewhere by hand, copy the `proofs` folder with it, or restore will report missing photos. Full backups don't need it.

**Restoring**
- **When the app opens with no data or damaged data**, and backups exist, it shows **"No data found in the app"** with **Restore latest**, **Choose another backup…** or **Start empty**. This is the reinstall / failed-update case.
- Any time: Export & Backup → **Restore** next to a backup, or **Restore from file…**.
- Restore asks for the password, shows what is inside (date, customers, entries, proofs) and asks to confirm.
- If the app has data, a manual backup of it is made first, so a restore can be undone.
- After a reinstall the backup password is gone from the app. Restoring sets it again from the password you typed.

**Encryption:** backup files (`.gtb`) are compressed and encrypted with **AES-256-GCM**. The key is made from the backup password with PBKDF2 (100,000 rounds). Without the password a backup cannot be opened or changed, even if someone copies the file.

- The password is remembered on this computer, so automatic backups run without asking.
- Changing the password affects new backups only. Older backups still need the old password.
- **Write the password down.** If it is lost, the backups cannot be opened by anyone.
- Only backups are encrypted. The live app data and proofs folder on this computer are not.

On macOS the app is sandboxed. It is given permission to write only to `~/Documents/Tally Backups/` and the old `~/Documents/Ghee Tally Backups/` (see `macos/Runner/*.entitlements`). Backups made by earlier versions inside the app folder are moved there automatically.

**Old folder name:** before the app was renamed to Tally, the backup folder was `Documents/Ghee Tally Backups`. When the app opens and finds that folder, it moves everything in it (backup files and the `proofs` folder) into `Documents/Tally Backups` and removes the old folder. Each file keeps its date, so the newest backup stays the newest. If the move cannot finish, nothing is lost: the files stay in the old folder and the app tries again the next time it opens.

### Where the data is saved
Data is saved automatically on this computer after every change, using `get_storage`. There is no internet or server.

- macOS: `~/Library/Containers/com.gheetally.gheeTally/Data/Documents/GetStorage.gs`
- Windows: `C:\Users\<you>\AppData\Roaming\com.gheetally\Tally\GetStorage.gs`. AppData is a hidden folder: to open it, type `%APPDATA%\com.gheetally\Tally` in the File Explorer address bar.

Proof files are stored next to it in a `proofs` folder (macOS: `~/Library/Containers/com.gheetally.gheeTally/Data/Documents/proofs/`; Windows: `%APPDATA%\com.gheetally\Tally\proofs\`).

On Windows the data is kept in the app's own AppData folder, not in Documents. Other programs also put files in Documents, and OneDrive often syncs it. Earlier Windows builds saved the data as `Documents\GetStorage.gs`, with photos in `Documents\proofs`. If that file is found when Tally opens, and Tally has no data in AppData yet, it is copied there once, with its photos. The old files are not deleted. After checking that everything is there, you can delete them.

Encrypted backups in `Documents/Tally Backups` (see above) protect against losing these files. On Windows this is `Documents\Tally Backups`; if OneDrive syncs Documents, the backups get a copy in the cloud too. Keep a copy of a recent backup outside this computer too.

---

## Updating the app

App data and backups are not stored inside `Tally.app`, so replacing the app keeps everything.

1. In the app: **Export & Backup → Back up now** (and **Save full backup to…** another drive for extra safety).
2. Quit the app.
3. Build: `rm -rf build/macos && fvm flutter build macos`. (On Windows, see "On Windows" above.)
4. Copy `build/macos/Build/Products/Release/Tally.app` into **Applications**, replacing the old one. If **Applications** still has `ghee_tally.app` (the app's earlier name), delete it. The data is not inside it.
5. Open it. The data is there. If it ever is not, the app offers to restore from `Documents/Tally Backups`. The first time Tally opens, it moves your backups there from the old `Documents/Ghee Tally Backups` folder.

Use only one copy of the app at a time. Every copy (including test builds) shares the same app data.

---

## Code structure

```
lib/
├── main.dart                     App start: loads storage, registers controllers and backup service
├── models.dart                   Customer, Entry, HistoryItem and CashTxn classes (+ JSON save/load)
├── utils.dart                    ₹ and kg formatting, dates, PayStatus colours
├── data/
│   └── indian_states.dart        All 28 states and 8 union territories
├── controllers/
│   ├── customer_filter.dart      Customer / State / District filter (used by several screens)
│   ├── tally_controller.dart     ALL business logic: add/edit/delete, change history, totals, Paid %, colour rules, saving
│   ├── dashboard_controller.dart Dashboard filter choices (period, customers, products, modes)
│   └── nav_controller.dart       Which screen is open, selected day, week and month, calendar and Customers filters
├── services/
│   ├── app_data.dart             Where the data file and proofs live (Windows: AppData), copying old Windows data
│   ├── backup_service.dart       Encrypted backup after every change, daily files, restore, password
│   ├── excel_export.dart         Builds the Excel file
│   ├── cashbook.dart             Opening / in / out / closing per account per day
│   └── stats.dart                Sales by product and payments by mode calculations
├── pages/
│   ├── startup_page.dart         Start screen with the Amutham logo
│   ├── home_page.dart            Left menu + switches between screens
│   ├── dashboard_page.dart
│   ├── daily_page.dart
│   ├── weekly_page.dart          Calendar and Table layouts
│   ├── monthly_page.dart         Month calendar
│   ├── customers_page.dart
│   ├── customer_detail_page.dart
│   ├── cashbook_page.dart        Cash book screen (Day and Month views, from widgets/cash_views.dart)
│   ├── backup_page.dart          Export & Backup screen
│   ├── history_page.dart         Change history screen
│   └── settings_page.dart
└── widgets/
    ├── common.dart               StatCard, StatusChip, CustomerTile, delete confirmation
    ├── cash_dialog.dart          Expense / money in / transfer / opening balance form
    ├── cash_views.dart           Cash book day view, week / month view, add buttons, Sales | Cash book switch
    ├── customer_dialog.dart      Add / edit customer form (code, name, phone, state, district, area, proofs)
    ├── customer_filter_bar.dart  Searchable customer picker + Customer / State / District filter row
    ├── history_view.dart         Change history cards, reason boxes, delete-with-reason dialog
    ├── restore_flow.dart         Restore steps and the startup "No data found" check
    ├── price_history.dart        Price history view on the customer page
    ├── proof_tile.dart           Preview of one proof file (photo or PDF), click to open
    └── entry_dialog.dart         Add / edit sale and payment form
```

### How GetX is used
- `Get.put(TallyController())` in `main.dart` creates one shared controller.
- Any screen gets it with `Get.find<TallyController>()`.
- Data lists are reactive: `customers` and `entries` are `.obs` lists.
- Screens wrap their UI in `Obx(() => ...)`. When data changes, the screen rebuilds by itself.
- Dialogs and page navigation use `Get.dialog(...)`, `Get.to(...)` and `Get.back()`.

### Common changes

| I want to... | Change this |
|---|---|
| Change the default 40% / 75% | `redBelow` and `greenFrom` in `controllers/tally_controller.dart` |
| Change the colour rule itself | `statusFor()` in `controllers/tally_controller.dart` |
| Change the starting payment modes | `defaultPaymentModes` in `controllers/tally_controller.dart` (only used the first time) |
| Change the starting product list | `defaultProducts` in `controllers/tally_controller.dart` (only used the first time; after that the saved list is used) |
| Change the Red/Yellow/Green colours or labels | `PayStatusX` in `utils.dart` |
| Add a field to an entry (e.g. invoice number) | `Entry` in `models.dart`, then `entry_dialog.dart` and the tables in the pages |
| Change the app's main colour | `colorSchemeSeed` in `main.dart` |

---

## Ideas for later
- Alert rule for "no payment in X days" (adjustable in Settings).
- Monthly report (product-wise totals, customer statements).
- Print or share a customer's statement.
