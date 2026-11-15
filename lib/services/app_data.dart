import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The folder with the app's data file (GetStorage.gs) and its proofs folder.
/// - macOS: the app's own Documents folder inside its sandbox
///   (~/Library/Containers/com.gheetally.gheeTally/Data/Documents), as always.
/// - Windows: AppData\Roaming\com.gheetally\Tally. Not the Documents folder:
///   other apps put files there too, and OneDrive often syncs it.
Future<Directory> appDataDir() async => Platform.isWindows
    ? getApplicationSupportDirectory()
    : getApplicationDocumentsDirectory();

/// Earlier Windows builds kept the data in the Documents folder
/// (Documents\GetStorage.gs and Documents\proofs). If that file holds this
/// app's data and [to] has no data file yet, copy the data and its proof
/// files into [to], pointing the customers' proofs at the new place.
/// The old files are left where they are; nothing is deleted.
/// Returns true if the data was copied.
Future<bool> copyOldWindowsData({required String from, required String to}) async {
  final oldFile = File(p.join(from, 'GetStorage.gs'));
  final newFile = File(p.join(to, 'GetStorage.gs'));
  if (newFile.existsSync() || !oldFile.existsSync()) return false;

  final Map<String, dynamic> data;
  try {
    data = Map<String, dynamic>.from(jsonDecode(await oldFile.readAsString()));
  } catch (_) {
    return false; // unreadable: leave it alone
  }
  // Another app may use the same file name: only take this app's data
  if (!data.containsKey('customers') && !data.containsKey('entries')) return false;

  final proofs = p.join(to, 'proofs');
  for (final cu in (data['customers'] as List? ?? [])) {
    if (cu is! Map) continue;
    final moved = <String>[];
    for (final path in List<String>.from(cu['proofs'] ?? [])) {
      final target = p.join(proofs, p.basename(path));
      final src = File(path);
      if (src.existsSync() && !File(target).existsSync()) {
        await Directory(proofs).create(recursive: true);
        await src.copy(target);
      }
      moved.add(target);
    }
    cu['proofs'] = moved;
  }

  // Write to a temp file first, then swap, so a crash never leaves half a file
  await Directory(to).create(recursive: true);
  final tmp = File('${newFile.path}.tmp');
  await tmp.writeAsString(jsonEncode(data), flush: true);
  await tmp.rename(newFile.path);
  return true;
}
