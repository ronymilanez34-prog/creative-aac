import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:creative_aac/services/image_sink.dart';
import 'package:creative_aac/services/obz_importer.dart';

/// A tiny .obz built in memory: four boards, one of them an orphan no
/// button leads to (the shape of a real export, 21.10: 94 boards in the
/// file, 25 reachable from home).
Uint8List buildObz({bool withManifest = true}) {
  Map<String, dynamic> board(String id, String name,
          List<Map<String, dynamic>> buttons, List<List<dynamic>> order) =>
      {
        'format': 'open-board-0.1',
        'id': id,
        'name': name,
        'buttons': buttons,
        'grid': {
          'rows': order.length,
          'columns': order.first.length,
          'order': order,
        },
      };

  final home = board('home', 'בית', [
    {'id': 1, 'label': 'שלום'},
    {'id': 2, 'label': 'אוכל', 'load_board': {'path': 'boards/food.obf'}},
    // Linked by id only — the manifest knows where "deep" lives.
    {'id': 3, 'label': 'משחק', 'load_board': {'id': 'deep'}},
    // A hidden button's link is a path the user cannot take.
    {
      'id': 4,
      'label': 'נסתר',
      'hidden': true,
      'load_board': {'path': 'boards/orphan.obf'},
    },
  ], [
    [1, 2],
    [3, 4],
  ]);
  final food = board('food', 'אוכל', [
    {'id': 1, 'label': 'מים'},
    {'id': 2, 'label': 'בית', 'load_board': {'path': 'boards/home.obf'}},
  ], [
    [1, 2],
  ]);
  final deep = board('deep', 'משחק', [
    {'id': 1, 'label': 'כדור'},
  ], [
    [1],
  ]);
  final orphan = board('orphan', 'יתום', [
    {'id': 1, 'label': 'יתום'},
  ], [
    [1],
  ]);

  final archive = Archive();
  void add(String name, Map<String, dynamic> json) {
    final bytes = utf8.encode(jsonEncode(json));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  if (withManifest) {
    add('manifest.json', {
      'format': 'open-board-0.1',
      'root': 'boards/home.obf',
      'paths': {
        'boards': {
          'home': 'boards/home.obf',
          'food': 'boards/food.obf',
          'deep': 'boards/deep.obf',
          'orphan': 'boards/orphan.obf',
        },
      },
    });
  }
  // Orphan first in the zip — order in the file must not matter.
  add('boards/orphan.obf', orphan);
  add('boards/deep.obf', deep);
  add('boards/food.obf', food);
  add('boards/home.obf', home);
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  test('obz import walks from the root and skips orphan boards', () async {
    final result = await ObzImporter().import(
      bytes: buildObz(),
      images: const NoopImageSink(),
    );

    // Home first, then its children (food, deep) — depth order, not zip
    // order. The orphan's word never enters the user's vocabulary.
    expect(
      result.words.map((w) => w.label).toList(),
      ['שלום', 'אוכל', 'משחק', 'מים', 'בית', 'כדור'],
    );
    expect(result.words.map((w) => w.label), isNot(contains('יתום')));
    expect(result.boardsCount, 3);
    expect(result.unreachableBoards, 1);
  });

  test('obz without a manifest root still imports every board', () async {
    final result = await ObzImporter().import(
      bytes: buildObz(withManifest: false),
      images: const NoopImageSink(),
    );
    expect(result.words.map((w) => w.label), contains('יתום'));
    expect(result.words.map((w) => w.label), contains('שלום'));
    expect(result.boardsCount, 4);
    expect(result.unreachableBoards, 0);
  });

  test('the sample board package still imports', () async {
    final bytes = File('docs/samples/sample-board.obz').readAsBytesSync();
    final sink = MemoryImageSink();
    final result = await ObzImporter().import(bytes: bytes, images: sink);
    expect(result.boardsCount, 1);
    expect(result.unreachableBoards, 0);
    expect(result.words, isNotEmpty);
    expect(result.imagesCount, greaterThan(0));
    expect(sink.images, isNotEmpty);
  });
}
