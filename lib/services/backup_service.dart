import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../controllers/tally_controller.dart';

/// What is inside a backup file, after it was unlocked with the password.
class BackupContents {
  final DateTime createdAt;
  final Map<String, dynamic> data;
  final Map<String, List<int>> proofFiles;
  final int missingProofs; // proof files that could not be found / opened
  BackupContents(this.createdAt, this.data, this.proofFiles, [this.missingProofs = 0]);

  int get customerCount => (data['customers'] as List).length;
  int get entryCount => (data['entries'] as List).length;
}

/// Encrypted backups, kept OUTSIDE the app in  Documents/Tally Backups
/// so they survive uninstalling, updating or damaged app data.
/// (Before the app was renamed to Tally the folder was "Ghee Tally Backups".
/// It is moved to the new name when the app opens.)
///
/// When backups happen:
/// - A few seconds after every change (new entry, edit, delete, settings…).
///   The day's backup file is UPDATED in place: daily_2026-11-12.gtb.
///   A new day starts a new file. So there is one file per day holding
///   that day's latest data.
/// - Daily files hold only the data (small, quick to update). Proof photos
///   are encrypted ONCE into  proofs/KEYID/NAME.gtp  and never re-written,
///   so a change does not copy every photo again.
/// - "Save full backup to…" and "Back up now" make one complete file with
///   the photos inside, for copying to a USB drive etc.
/// - When the app opens, if today has no backup yet.
/// - "Back up now" makes a separate manual_DATE_TIME.gtb file.
/// Automatic backups never run while the app has no data, so an empty or
/// damaged app can never overwrite good backups.
///
/// Kept: the newest [keepDaily] daily files and [keepManual] manual files.
///
/// Encryption: compressed, then AES-256-GCM. The key comes from the backup
/// password (PBKDF2-HMAC-SHA256, 100,000 rounds). Without the password a
/// backup cannot be read or changed.
/// File layout (.gtb): "GTB1" | salt (16) | nonce (12) | mac (16) | encrypted data
class BackupService extends GetxService {
  static const keepDaily = 60;
  static const keepManual = 20;
  /// The backup folder. The macOS entitlements allow writing only to this
  /// folder and [oldFolderName]. Renaming it needs a move like [moveFolder].
  static const folderName = 'Tally Backups';

  /// The folder's name before the app was renamed to Tally. Backups found
  /// there are moved into [folderName] when the app opens.
  static const oldFolderName = 'Ghee Tally Backups';
  static const _magic = 'GTB1';
  static const _delay = Duration(seconds: 3); // wait for quick edits to finish

  /// Tests point backups at a temp folder.
  static String? dirOverride;

  final _box = GetStorage();
  final _aes = AesGcm.with256bits();
  final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);

  final hasPassword = false.obs;
  final lastBackup = Rxn<DateTime>();
  final backups = <File>[].obs; // newest first
  final busy = false.obs;
  final lastError = RxnString();
  final folderPath = ''.obs;

  Timer? _timer;
  bool _again = false; // a change came in while a backup was running
  Future<File?>? _running; // the backup in progress, if any
  Future<void> _moving = Future.value(); // moving old backups in, when the app opens

  TallyController get _tally => Get.find<TallyController>();

  @override
  void onInit() {
    super.onInit();
    hasPassword.value = _box.read('backupKey') != null;
    final last = _box.read<String>('lastBackup');
    lastBackup.value = last == null ? null : DateTime.parse(last);

    // Back up a few seconds after every change
    ever(_tally.changes, (_) => _schedule());

    // Listing and making backups wait for this move to finish
    _moving = _moveOldBackups();
    _moving.then((_) async {
      await refreshList();
      await _backupIfNoneToday();
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  // ---------- Folder ----------

  /// The Documents folder in the user's home folder.
  /// On macOS the app runs in a sandbox, where HOME points inside the app's
  /// own container, so the real home folder is worked out from it.
  Future<String> _documentsPath() async {
    if (Platform.isMacOS) {
      var home = Platform.environment['HOME'] ?? '';
      final i = home.indexOf('/Library/Containers/');
      if (i > 0) home = home.substring(0, i);
      return p.join(home, 'Documents');
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// Documents/Tally Backups in the user's home folder.
  Future<Directory> backupsDir() async {
    final path = dirOverride ?? p.join(await _documentsPath(), folderName);
    folderPath.value = path;
    return Directory(path).create(recursive: true);
  }

  /// Moves backups made by earlier versions into the backup folder:
  /// - "Ghee Tally Backups" (the folder before the app was renamed to Tally)
  /// - the "backups" folder inside the app (very early Mac versions only;
  ///   on Windows that would be the shared Documents\backups folder)
  /// Never throws: if a move fails, the files stay where they were and the
  /// move is tried again the next time the app opens.
  Future<void> _moveOldBackups() async {
    if (dirOverride != null) return;
    try {
      final docs = await _documentsPath();
      await moveFolder(Directory(p.join(docs, oldFolderName)),
          Directory(p.join(docs, folderName)));
    } catch (_) {}
    if (!Platform.isMacOS) return;
    try {
      final old =
          Directory(p.join((await getApplicationDocumentsDirectory()).path, 'backups'));
      if (!await old.exists()) return;
      final dir = await backupsDir();
      for (final f in old.listSync().whereType<File>().where((f) => f.path.endsWith('.gtb'))) {
        final target = p.join(dir.path, p.basename(f.path));
        if (!File(target).existsSync()) await f.copy(target);
        await f.delete();
      }
    } catch (_) {}
  }

  /// Moves everything in [from] (backup files and the proofs folder) into [to],
  /// then removes [from].
  /// - If [to] does not exist yet, the whole folder is renamed in one step.
  /// - Otherwise each file is copied, then the old one deleted. A file that is
  ///   in both folders keeps the newer copy.
  /// Files keep their "last changed" time, so the newest backup stays newest.
  /// An old file is deleted only after its copy is safely in [to].
  static Future<void> moveFolder(Directory from, Directory to) async {
    if (!await from.exists()) return;
    if (!await to.exists()) {
      try {
        await to.parent.create(recursive: true);
        await from.rename(to.path);
        return;
      } catch (_) {} // e.g. not allowed: move file by file instead
    }
    await to.create(recursive: true);
    final items = from.listSync(recursive: true);
    for (final f in items.whereType<File>()) {
      final target = File(p.join(to.path, p.relative(f.path, from: from.path)));
      final changed = f.lastModifiedSync();
      if (!target.existsSync() || changed.isAfter(target.lastModifiedSync())) {
        await target.parent.create(recursive: true);
        final tmp = File('${target.path}.moving');
        await f.copy(tmp.path);
        await tmp.setLastModified(changed);
        await tmp.rename(target.path);
      }
      await f.delete();
    }
    // Remove the emptied folders, deepest first
    final dirs = items.whereType<Directory>().toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final d in [...dirs, from]) {
      try {
        await d.delete(); // only removes empty folders
      } catch (_) {}
    }
  }

  Future<void> refreshList() async {
    await _moving;
    final dir = await backupsDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gtb'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    backups.assignAll(files);
  }

  static bool isManual(File f) => p.basename(f.path).startsWith('manual_');

  // ---------- Password ----------

  /// Sets (or changes) the backup password. It is remembered on this
  /// computer as a derived key, so automatic backups run without asking.
  /// Old backups still need the password they were made with.
  Future<void> setPassword(String password) async {
    final salt = _randomBytes(16);
    final key = await _deriveKey(password, salt);
    _box.write('backupSalt', base64Encode(salt));
    _box.write('backupKey', base64Encode(key));
    hasPassword.value = true;
  }

  // ---------- Automatic backups ----------

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_delay, () => backupNow());
  }

  Future<void> _backupIfNoneToday() async {
    final today = File(p.join((await backupsDir()).path, _dailyName(DateTime.now())));
    if (!await today.exists()) await backupNow();
  }

  String _dailyName(DateTime d) => 'daily_${DateFormat('yyyy-MM-dd').format(d)}.gtb';

  // ---------- Backup ----------

  /// Makes a backup. [manual] = a separate timestamped file ("Back up now").
  /// Returns the file, or null if it did not run or failed.
  Future<File?> backupNow({bool manual = false}) async {
    if (!hasPassword.value) return null;
    if (!manual && !_tally.hasData) return null; // never back up an empty app
    if (_running != null) {
      if (!manual) {
        _again = true; // run again when the current one finishes
        return null;
      }
      await _running; // "Back up now" waits for the running one, then runs
      return backupNow(manual: true);
    }
    final run = _backup(manual);
    _running = run;
    try {
      return await run;
    } finally {
      _running = null;
      if (_again) {
        _again = false;
        _schedule();
      }
    }
  }

  Future<File?> _backup(bool manual) async {
    busy.value = true;
    lastError.value = null;
    try {
      await _moving;
      final now = DateTime.now();
      if (!manual) await _syncProofs(); // only writes photos not saved yet
      final bytes = await _encrypt(now, withProofs: manual);
      final dir = await backupsDir();
      final name = manual
          ? 'manual_${DateFormat('yyyy-MM-dd_HHmmss').format(now)}.gtb'
          : _dailyName(now);
      final file = File(p.join(dir.path, name));

      // Write to a temp file first, then swap, so a crash never leaves
      // a half-written backup.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);

      lastBackup.value = now;
      _box.write('lastBackup', now.toIso8601String());
      await _deleteOld();
      return file;
    } catch (e) {
      lastError.value = e.toString();
      return null;
    } finally {
      busy.value = false;
    }
  }

  /// A complete backup (data + photos) as bytes, for "Save full backup to…".
  Future<Uint8List> fullBackupBytes() => _encrypt(DateTime.now(), withProofs: true);

  /// The backup's data, encrypted. [withProofs] puts the photos inside the
  /// file too; otherwise only their names are listed (photos are in proofs/).
  Future<Uint8List> _encrypt(DateTime now, {required bool withProofs}) async {
    final names = <String>[];
    final proofs = <String, String>{};
    for (final cu in _tally.customers) {
      for (final path in cu.proofs) {
        names.add(p.basename(path));
        if (withProofs) {
          final f = File(path);
          if (await f.exists()) {
            proofs[p.basename(path)] = base64Encode(await f.readAsBytes());
          }
        }
      }
    }
    final json = jsonEncode({
      'app': 'Tally',
      'version': 2,
      'createdAt': now.toIso8601String(),
      'data': _tally.exportData(),
      'proofNames': names,
      'proofs': proofs,
    });
    return _seal(gzip.encode(utf8.encode(json)));
  }

  /// Encrypts [clear] with the saved key: "GTB1" | salt | nonce | mac | data.
  Future<Uint8List> _seal(List<int> clear) async {
    final salt = base64Decode(_box.read('backupSalt'));
    final key = SecretKey(base64Decode(_box.read('backupKey')));
    final box = await _aes.encrypt(clear, secretKey: key);
    return (BytesBuilder()
          ..add(ascii.encode(_magic))
          ..add(salt)
          ..add(box.nonce)
          ..add(box.mac.bytes)
          ..add(box.cipherText))
        .toBytes();
  }

  /// Folder for encrypted photos, one per password ("key id" = start of salt),
  /// so photos always open with the same password as the daily files using them.
  String _keyId(List<int> salt) =>
      salt.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Encrypts each proof photo once. Photos already in the backup are skipped.
  Future<void> _syncProofs() async {
    final salt = base64Decode(_box.read('backupSalt'));
    final dir = await Directory(
            p.join((await backupsDir()).path, 'proofs', _keyId(salt)))
        .create(recursive: true);
    for (final cu in _tally.customers) {
      for (final path in cu.proofs) {
        final target = File(p.join(dir.path, '${p.basename(path)}.gtp'));
        if (await target.exists()) continue;
        final src = File(path);
        if (!await src.exists()) continue;
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsBytes(await _seal(await src.readAsBytes()), flush: true);
        await tmp.rename(target.path);
      }
    }
  }

  Future<void> _deleteOld() async {
    await refreshList();
    final daily = backups.where((f) => p.basename(f.path).startsWith('daily_'));
    final manual = backups.where(isManual);
    for (final f in [...daily.skip(keepDaily), ...manual.skip(keepManual)]) {
      try {
        await f.delete();
      } catch (_) {}
    }
    await refreshList();
  }

  // ---------- Restore ----------

  /// Opens a backup file with [password].
  /// Throws a readable message if the file or password is wrong.
  Future<BackupContents> readBackup(String path, String password) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 48 || ascii.decode(bytes.sublist(0, 4)) != _magic) {
      throw 'This is not a Tally backup file.';
    }
    final salt = bytes.sublist(4, 20);
    final key = SecretKey(await _deriveKey(password, salt));
    final List<int> clear;
    try {
      clear = await _open(bytes, key);
    } on SecretBoxAuthenticationError {
      throw 'Wrong password, or the file is damaged.';
    }

    final json = jsonDecode(utf8.decode(gzip.decode(clear))) as Map<String, dynamic>;
    final proofs = <String, List<int>>{
      for (final e in (json['proofs'] as Map? ?? {}).entries)
        e.key.toString(): base64Decode(e.value as String),
    };

    // Photos not inside the file: read them from proofs/KEYID next to it
    var missing = 0;
    final photoDir = p.join(p.dirname(path), 'proofs', _keyId(salt));
    for (final name in List<String>.from(json['proofNames'] ?? [])) {
      if (proofs.containsKey(name)) continue;
      try {
        proofs[name] = await _open(
            await File(p.join(photoDir, '$name.gtp')).readAsBytes(), key);
      } catch (_) {
        missing++;
      }
    }
    return BackupContents(
      DateTime.parse(json['createdAt']),
      Map<String, dynamic>.from(json['data']),
      proofs,
      missing,
    );
  }

  /// Decrypts a "GTB1" file with [key].
  Future<List<int>> _open(List<int> bytes, SecretKey key) => _aes.decrypt(
        SecretBox(bytes.sublist(48),
            nonce: bytes.sublist(20, 32), mac: Mac(bytes.sublist(32, 48))),
        secretKey: key,
      );

  /// Replaces all current data with [contents].
  /// If the app has data, a manual backup of it is made first, so the
  /// restore can be undone. If no backup password is set on this computer
  /// (e.g. after reinstalling), the password used to open the backup is set.
  Future<void> restore(BackupContents contents, String password) async {
    if (!hasPassword.value) await setPassword(password);
    if (_tally.hasData) await backupNow(manual: true);
    await _tally.importData(contents.data, contents.proofFiles);
    _tally.loadProblem = null;
  }

  // ---------- Helpers ----------

  Future<List<int>> _deriveKey(String password, List<int> salt) async {
    final k = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    return k.extractBytes();
  }

  List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(256));
  }
}
