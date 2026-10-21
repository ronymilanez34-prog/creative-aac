import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creative_aac/services/board_store_web.dart';

/// The web store, exercised on the VM with an in-memory IndexedDB — the
/// pictures must come back as data URIs on words AND on the board map.
void main() {
  test('web store keeps the pictures in IndexedDB and hands out data URIs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = BoardStore(idbFactory: newIdbFactoryMemory());
    final result = await store.importFromBytes(
        File('docs/samples/sample-board.obz').readAsBytesSync());
    expect(result.imagesCount, 12);
    expect(result.imagesDropped, 0);
    // The result itself carries the pictures — the import screen shows
    // them at once, without a reopen.
    expect(result.words.where((w) => w.imagePath != null).length, 12);
    expect(result.layout!.home!.buttons.first.imagePath, startsWith('data:image/'));

    final words = await store.load();
    expect(words.where((w) => w.imagePath?.startsWith('data:image/png;base64,') ?? false).length, 12);

    final layout = await store.loadLayout();
    final buttons = layout!.home!.buttons;
    expect(buttons.where((b) => b.imagePath != null).length, 12);
    expect(buttons.first.imagePath, startsWith('data:image/'));

    // Nothing of the pictures in localStorage any more (the old overflow).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('creative_aac.board_images.v1'), isNull);

    await store.clear();
    expect(await store.load(), isEmpty);
    expect(await store.loadLayout(), isNull);
  });

  test('an import made before 21.10 still shows its pictures', () async {
    SharedPreferences.setMockInitialValues({
      'creative_aac.board_words.v1':
          '[{"id":"w0","label":"מים","imageFile":"img_0.png"}]',
      'creative_aac.board_images.v1': '{"img_0.png":"data:image/png;base64,AAAA"}',
    });
    final store = BoardStore(idbFactory: newIdbFactoryMemory());
    final words = await store.load();
    expect(words.single.imagePath, 'data:image/png;base64,AAAA');
  });
}
