import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../controllers/tally_controller.dart';
import '../services/backup_service.dart';
import '../utils.dart';

String backupWhen(DateTime d) => '${longDate(d)} ${DateFormat('h:mm a').format(d)}';

void _snack(String title, String msg) =>
    Get.snackbar(title, msg, snackPosition: SnackPosition.BOTTOM, maxWidth: 520);

/// Restore steps: (pick file) -> password -> show what is inside -> confirm -> restore.
/// Returns true if data was restored.
Future<bool> restoreFlow([String? path]) async {
  final b = Get.find<BackupService>();
  if (path == null) {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose a Tally backup (.gtb)',
      type: FileType.custom,
      allowedExtensions: ['gtb'],
    );
    if (files.isEmpty || files.first.path == null) return false;
    path = files.first.path!;
  }

  final pw = await Get.dialog<String>(AskPasswordDialog(fileName: p.basename(path)));
  if (pw == null) return false;

  final BackupContents contents;
  try {
    contents = await b.readBackup(path, pw);
  } catch (e) {
    _snack('Could not open backup', e.toString());
    return false;
  }

  final hasData = Get.find<TallyController>().hasData;
  final ok = await Get.dialog<bool>(AlertDialog(
    title: const Text('Restore this backup?'),
    content: Text('Backup from ${backupWhen(contents.createdAt)}\n'
        '${contents.customerCount} customers, ${contents.entryCount} entries, '
        '${contents.proofFiles.length} proof files.\n'
        '${contents.missingProofs > 0 ? '⚠ ${contents.missingProofs} proof photo(s) were not found next to this backup and will be missing.\n' : ''}\n'
        '${hasData ? 'This REPLACES all data currently in the app.\n'
            'A backup of the current data is made first, so you can go back.' : 'The app is empty, so nothing will be lost.'}'),
    actions: [
      TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Get.back(result: true), child: const Text('Restore')),
    ],
  ));
  if (ok != true) return false;
  await b.restore(contents, pw);
  _snack('Restored', 'Data from ${backupWhen(contents.createdAt)} is now in the app.');
  return true;
}

/// Asks for the password of a backup being restored.
class AskPasswordDialog extends StatefulWidget {
  final String fileName;
  const AskPasswordDialog({super.key, required this.fileName});

  @override
  State<AskPasswordDialog> createState() => _AskPasswordDialogState();
}

class _AskPasswordDialogState extends State<AskPasswordDialog> {
  final _pw = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup password'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.fileName, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _pw,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password used when this backup was made'),
              onSubmitted: (_) => Get.back(result: _pw.text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Get.back(result: _pw.text), child: const Text('Open backup')),
      ],
    );
  }
}

/// Runs once when the app opens. If the app's own data is empty or damaged
/// but backups exist, offers to restore the latest one.
Future<void> checkForRecovery() async {
  final tally = Get.find<TallyController>();
  final b = Get.find<BackupService>();
  await b.refreshList();
  if (tally.hasData && tally.loadProblem == null) return; // all good
  if (b.backups.isEmpty) return; // first use, nothing to restore

  final latest = b.backups.first;
  await Get.dialog(
    AlertDialog(
      icon: const Icon(Icons.restore, size: 36),
      title: Text(tally.loadProblem != null
          ? 'The app data could not be read'
          : 'No data found in the app'),
      content: SizedBox(
        width: 480,
        child: Text(
          'This can happen after reinstalling or updating the app.\n\n'
          'Found ${b.backups.length} backup(s) in:\n${b.folderPath.value}\n\n'
          'Latest: ${p.basename(latest.path)}\n'
          '(saved ${backupWhen(latest.lastModifiedSync())})\n\n'
          'Restore it now? You will need the backup password.',
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Start empty')),
        OutlinedButton(
          onPressed: () async {
            if (await restoreFlow()) Get.back();
          },
          child: const Text('Choose another backup…'),
        ),
        FilledButton(
          onPressed: () async {
            if (await restoreFlow(latest.path)) Get.back();
          },
          child: const Text('Restore latest'),
        ),
      ],
    ),
    barrierDismissible: false,
  );
}

/// Helper for the backups list.
String fileSize(File f) {
  try {
    final kb = f.lengthSync() / 1024;
    return kb < 1024 ? '${kb.toStringAsFixed(0)} KB' : '${(kb / 1024).toStringAsFixed(1)} MB';
  } catch (_) {
    return '';
  }
}
