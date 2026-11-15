import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghee_tally/services/app_data.dart';

/// Windows: data saved by earlier builds in Documents is copied once into
/// the app's own folder (AppData). Nothing is deleted.
void main() {
  late Directory tmp;
  late Directory docs; // the old place (Documents)
  late Directory app; // the new place (AppData\...\Tally)

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tally_app_data');
    docs = await Directory('${tmp.path}/Documents').create();
    app = Directory('${tmp.path}/AppData/com.gheetally/Tally');
  });
  tearDown(() => tmp.delete(recursive: true));

  Map<String, dynamic> read(Directory d) =>
      jsonDecode(File('${d.path}/GetStorage.gs').readAsStringSync());

  test('old data and its proof photos are copied; the old files stay', () async {
    final photo = File('${docs.path}/proofs/123_id.png')
      ..createSync(recursive: true)
      ..writeAsStringSync('photo');
    File('${docs.path}/GetStorage.gs').writeAsStringSync(jsonEncode({
      'customers': [
        {'id': 'c1', 'name': 'Ravi', 'proofs': [photo.path]},
        {'id': 'c2', 'name': 'No proofs'},
      ],
      'entries': [
        {'id': 'e1', 'customerId': 'c1'}
      ],
    }));

    expect(await copyOldWindowsData(from: docs.path, to: app.path), isTrue);

    final data = read(app);
    expect((data['entries'] as List).length, 1);
    final newPhoto = '${app.path}/proofs/123_id.png';
    expect(data['customers'][0]['proofs'], [newPhoto]);
    expect(File(newPhoto).readAsStringSync(), 'photo');
    expect(data['customers'][1]['proofs'], isEmpty);
    // Nothing deleted from Documents
    expect(File('${docs.path}/GetStorage.gs').existsSync(), isTrue);
    expect(photo.existsSync(), isTrue);
    expect(File('${app.path}/GetStorage.gs.tmp').existsSync(), isFalse);
  });

  test('never overwrites data already in the app folder', () async {
    File('${docs.path}/GetStorage.gs').writeAsStringSync(jsonEncode({'customers': []}));
    File('${app.path}/GetStorage.gs')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'entries': [], 'mine': true}));

    expect(await copyOldWindowsData(from: docs.path, to: app.path), isFalse);
    expect(read(app)['mine'], isTrue);
  });

  test("another app's file, an unreadable file, or no file: nothing copied", () async {
    final old = File('${docs.path}/GetStorage.gs');

    old.writeAsStringSync(jsonEncode({'theme': 'dark'})); // another app
    expect(await copyOldWindowsData(from: docs.path, to: app.path), isFalse);

    old.writeAsStringSync('not json');
    expect(await copyOldWindowsData(from: docs.path, to: app.path), isFalse);

    old.deleteSync();
    expect(await copyOldWindowsData(from: docs.path, to: app.path), isFalse);
    expect(app.existsSync(), isFalse);
  });
}
