import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../controllers/customer_filter.dart';
import '../controllers/tally_controller.dart';
import '../services/backup_service.dart';
import '../services/excel_export.dart';
import '../utils.dart';
import '../widgets/customer_filter_bar.dart';
import '../widgets/restore_flow.dart';

enum _Period { thisMonth, lastMonth, all, custom }

/// Excel export + encrypted backups.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final b = Get.find<BackupService>();
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  final _who = CustomerFilter(); // which customers to export

  // ---------- Excel ----------

  (DateTime?, DateTime?, String) _range() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.thisMonth:
        final s = DateTime(now.year, now.month);
        return (s, DateTime(now.year, now.month + 1, 0), DateFormat('MMMM yyyy').format(s));
      case _Period.lastMonth:
        final s = DateTime(now.year, now.month - 1);
        return (s, DateTime(now.year, now.month, 0), DateFormat('MMMM yyyy').format(s));
      case _Period.all:
        return (null, null, 'All time');
      case _Period.custom:
        final r = _custom!;
        return (r.start, r.end, '${shortDate(r.start)} - ${shortDate(r.end)}');
    }
  }

  Future<void> _exportExcel() async {
    if (_period == _Period.custom && _custom == null) {
      _snack('Choose dates', 'Pick a start and end date first.');
      return;
    }
    final tally = Get.find<TallyController>();
    final ids = _who.matchingIds(tally.customers);
    if (ids != null && ids.isEmpty) {
      _snack('No customers', 'No customer matches the chosen customer / state / district.');
      return;
    }
    final (from, to, label) = _range();
    final bytes =
        buildExcel(from: from, to: to, customerFilter: _who.isActive ? _who.matches : null);
    // e.g. "Tally - November 2026 - Tamil Nadu · Erode.xlsx"
    final who = _who.isActive ? ' - ${_who.describe(tally.customerName)}' : '';
    final name = 'Tally - $label$who'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Excel file',
      fileName: '$name.xlsx',
      bytes: bytes,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (uri == null) return; // cancelled
    Get.snackbar('Excel saved', p.basename(uri.toFilePath()),
        snackPosition: SnackPosition.BOTTOM,
        maxWidth: 520,
        duration: const Duration(seconds: 6),
        mainButton: TextButton(onPressed: () => launchUrl(uri), child: const Text('Open')));
  }

  // ---------- Backup ----------

  Future<void> _setPassword() async {
    final pw = await Get.dialog<String>(_PasswordDialog(changing: b.hasPassword.value));
    if (pw == null) return;
    await b.setPassword(pw);
    _snack('Backup password saved', 'Backups are now on.');
    await b.backupNow();
  }

  Future<void> _backupNow() async {
    final f = await b.backupNow(manual: true);
    if (f != null) {
      _snack('Backup done', p.basename(f.path));
    } else {
      _snack('Backup failed', b.lastError.value ?? 'Unknown error');
    }
  }

  /// One complete file (data + photos) saved wherever the user picks.
  Future<void> _saveFullCopy() async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save a full backup (e.g. on a USB drive)',
      fileName: 'tally_full_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.gtb',
      bytes: await b.fullBackupBytes(),
    );
    if (uri != null) _snack('Full backup saved', uri.toFilePath());
  }

  void _snack(String title, String msg) => Get.snackbar(title, msg,
      snackPosition: SnackPosition.BOTTOM, maxWidth: 520);

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Export & Backup', style: t.headlineMedium),
        const SizedBox(height: 20),

        // ===== Excel =====
        _Section(
          icon: Icons.table_view,
          title: 'Export to Excel',
          children: [
            const Text('Creates an .xlsx file with 7 sheets: Customers (place, totals and '
                'status), Entries (every sale and payment), Products (kg and amount per '
                'product), Daily (totals per day), Change history (edits and deletions), '
                'Cash book (each account, each day) and Expenses & money in. The two cash '
                'sheets are left out when only some customers are exported.'),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<_Period>(
                segments: const [
                  ButtonSegment(value: _Period.thisMonth, label: Text('This month')),
                  ButtonSegment(value: _Period.lastMonth, label: Text('Last month')),
                  ButtonSegment(value: _Period.all, label: Text('All time')),
                  ButtonSegment(value: _Period.custom, label: Text('Choose dates')),
                ],
                selected: {_period},
                onSelectionChanged: (s) async {
                  setState(() => _period = s.first);
                  if (s.first == _Period.custom) {
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: _custom,
                    );
                    if (r != null) setState(() => _custom = r);
                  }
                },
              ),
              if (_period == _Period.custom && _custom != null)
                Text('${shortDate(_custom!.start)} – ${shortDate(_custom!.end)}'),
            ]),
            const SizedBox(height: 14),
            Text('Customers (optional): all, one customer, or a state / district',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            CustomerFilterBar(_who),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _exportExcel,
              icon: const Icon(Icons.download),
              label: const Text('Export to Excel'),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ===== Backup =====
        Obx(() => _Section(
              icon: Icons.lock,
              title: 'Encrypted backup',
              children: [
                const Text(
                    'Your data is kept in two places: the app\'s own data, and a separate '
                    'backup folder outside the app. If the app is uninstalled, updated or its '
                    'data gets damaged, the backups are still there and can be restored.\n\n'
                    'A few seconds after every change, today\'s backup file is updated. '
                    'A new day starts a new file, so each file holds that day\'s final data '
                    '(the last ${BackupService.keepDaily} days are kept). Daily files hold only '
                    'the data; proof photos are saved once in a "proofs" folder and not copied '
                    'again. "Back up now" and "Save full backup to…" make one complete file '
                    'with the photos inside (last ${BackupService.keepManual} manual files kept).\n'
                    'Backups include customers, entries, products, settings, change history and '
                    'proof files. They are encrypted with AES-256 using your backup password, '
                    'so nobody can open them without it.'),
                const SizedBox(height: 8),
                SelectableText('Backup folder: ${b.folderPath.value}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                if (!b.hasPassword.value) ...[
                  _Notice(
                    color: Colors.orange,
                    icon: Icons.warning_amber,
                    text: 'Backups are OFF. Set a backup password to turn them on.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _setPassword,
                    icon: const Icon(Icons.key),
                    label: const Text('Set backup password'),
                  ),
                ] else ...[
                  _Notice(
                    color: Colors.green,
                    icon: Icons.check_circle,
                    text: b.lastBackup.value == null
                        ? 'Backups are ON. The first one is made after your next change.'
                        : 'Backups are ON.  Last backup: ${backupWhen(b.lastBackup.value!)}.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    FilledButton.icon(
                      onPressed: b.busy.value ? null : _backupNow,
                      icon: b.busy.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.backup),
                      label: Text(b.busy.value ? 'Backing up…' : 'Back up now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saveFullCopy,
                      icon: const Icon(Icons.usb),
                      label: const Text('Save full backup to…'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => restoreFlow(),
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore from file…'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async =>
                          launchUrl(Uri.directory((await b.backupsDir()).path)),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open backups folder'),
                    ),
                    TextButton.icon(
                      onPressed: _setPassword,
                      icon: const Icon(Icons.key),
                      label: const Text('Change password'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Text('Saved backups', style: t.titleSmall),
                  const SizedBox(height: 4),
                  if (b.backups.isEmpty) const Text('None yet.'),
                  for (final f in b.backups)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(BackupService.isManual(f)
                          ? Icons.lock_person_outlined
                          : Icons.lock_clock_outlined),
                      title: Text(p.basename(f.path)),
                      subtitle: Text('${BackupService.isManual(f) ? 'Manual' : 'Daily'}'
                          '  ·  saved ${backupWhen(f.lastModifiedSync())}  ·  ${fileSize(f)}'),
                      trailing: TextButton(
                          onPressed: () => restoreFlow(f.path),
                          child: const Text('Restore')),
                    ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Write the backup password down and keep it safe. If it is lost, '
                  'the backups cannot be opened by anyone.',
                  style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            )),
      ],
    );
  }
}

// ---------- Small widgets ----------

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _Section({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Notice({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

/// Set / change the backup password (typed twice).
class _PasswordDialog extends StatefulWidget {
  final bool changing;
  const _PasswordDialog({required this.changing});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _show = false;

  void _save() {
    if (_form.currentState!.validate()) Get.back(result: _pw.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.changing ? 'Change backup password' : 'Set backup password'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _pw,
              autofocus: true,
              obscureText: !_show,
              decoration: InputDecoration(
                labelText: 'Password (at least 6 characters)',
                suffixIcon: IconButton(
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Use at least 6 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pw2,
              obscureText: !_show,
              decoration: const InputDecoration(labelText: 'Type it again'),
              validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Text(
              widget.changing
                  ? 'New backups will use the new password. Older backups still need '
                      'the old password to restore.'
                  : 'Write this password down. Without it, backups cannot be restored.',
              style: const TextStyle(fontSize: 12),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save password')),
      ],
    );
  }
}
