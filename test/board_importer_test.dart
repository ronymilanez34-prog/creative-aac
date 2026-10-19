import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:creative_aac/services/board_importer.dart';
import 'package:creative_aac/services/image_sink.dart';
import 'package:creative_aac/services/obz_importer.dart';
import 'package:creative_aac/services/sqlite_reader.dart';

/// Fixtures in test/fixtures are SYNTHETIC: TouchChat's real schema (from a
/// real TouchChat HD export, 19.10.2026) with invented words — no friend's
/// data is ever committed. Regenerate with test/fixtures/make_touchchat_fixture.py.
Uint8List fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('SqliteReader', () {
    test('reads TouchChat tables, rowid alias and all rows across b-tree pages',
        () {
      final db = SqliteReader(fixture('touchchat_sample.c4v'));
      expect(db.hasTable('buttons'), isTrue);
      expect(db.columns('buttons'),
          ['id', 'resource_id', 'label', 'message', 'symbol_link_id', 'visible', 'button_style_id']);
      final buttons = db.rows('buttons');
      // 7 home + 4 page-1 + 700 fillers + 1 orphan
      expect(buttons.length, 712);
      expect(buttons.first['id'], 1); // INTEGER PRIMARY KEY carries the rowid
      // A 900-letter label lives on overflow pages and comes back whole.
      expect(buttons.any((b) => b['label'] == 'ש' * 900), isTrue);
    });

    test('parses column lists with quotes and table constraints', () {
      final c = SqliteReader.parseColumns(
          'CREATE TABLE "t" ("id" INTEGER PRIMARY KEY, [a b] TEXT, `c` BLOB, '
          'd NUMERIC(10,2), UNIQUE(a,c), CONSTRAINT k CHECK (d > 0))');
      expect(c.names, ['id', 'a b', 'c', 'd']);
      expect(c.rowidIndex, 0);
    });

    test('rejects non-SQLite bytes', () {
      expect(SqliteReader.isSqlite(Uint8List.fromList(List.filled(200, 0))), isFalse);
      expect(() => SqliteReader(Uint8List(200)), throwsA(isA<SqliteFormatException>()));
    });
  });

  group('BoardImporter.detect', () {
    test('knows each format by its content', () {
      expect(BoardImporter.detect(fixture('touchchat_sample.ce')), BoardFormat.touchChatZip);
      expect(BoardImporter.detect(fixture('touchchat_sample.c4v')), BoardFormat.touchChatDb);
      expect(BoardImporter.detect(File('docs/samples/sample-board.obz').readAsBytesSync()),
          BoardFormat.openBoard);
      expect(BoardImporter.detect(Uint8List.fromList(utf8.encode('  {"buttons":[]}'))),
          BoardFormat.openBoard);
      expect(BoardImporter.detect(Uint8List.fromList(utf8.encode('%PDF-1.7 ...'))),
          BoardFormat.pdf);
      expect(BoardImporter.detect(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0])),
          BoardFormat.image);
      expect(BoardImporter.detect(Uint8List.fromList(utf8.encode('hello world'))),
          BoardFormat.unknown);
    });

    test('a picture of a board gets a clear, kind message (not a crash)', () async {
      expect(
        () => BoardImporter().import(
            bytes: Uint8List.fromList(utf8.encode('%PDF-1.7')), images: const NoopImageSink()),
        throwsA(isA<ObzFormatException>()),
      );
    });
  });

  group('TouchChat import', () {
    test('.ce: home page first, system buttons out, spoken text and picture kept',
        () async {
      final sink = MemoryImageSink();
      final r = await BoardImporter()
          .import(bytes: fixture('touchchat_sample.ce'), images: sink);
      final labels = r.words.map((w) => w.label).toList();

      // HOME (page 2) before page 1, each page in cell order.
      expect(labels.take(3), ['אמא', 'כלב', 'לגן']);
      expect(labels.indexOf('פירות'), greaterThan(labels.indexOf('לגן')));
      // Keyboard, delete, hidden and empty-label buttons are not words.
      for (final gone in ['מקלדת', 'מחיקה', 'סוד', '']) {
        expect(labels, isNot(contains(gone)));
      }
      // TouchChat's spoken text (with nikud) is kept for the voice.
      expect(r.words.first.speak, 'אִמָּא');
      // "מֶלון" and "מלון" are one word.
      expect(labels.where((l) => l.replaceAll(RegExp('[֑-ׇ]'), '') == 'מלון').length, 1);
      // The custom photo comes along; a built-in symbol does not.
      final dog = r.words.firstWhere((w) => w.label == 'כלב');
      expect(dog.imageFile, isNotNull);
      expect(sink.images.length, 1);
      expect(r.words.firstWhere((w) => w.label == 'לגן').imageFile, isNull);
      // Capped like any board.
      expect(r.words.length, ObzImporter.maxWords);
    });

    test('.c4v alone imports the same words (no pictures without Images.c4s)',
        () async {
      final r = await BoardImporter()
          .import(bytes: fixture('touchchat_sample.c4v'), images: MemoryImageSink());
      expect(r.words.take(3).map((w) => w.label), ['אמא', 'כלב', 'לגן']);
      expect(r.imagesCount, 0);
    });

    test('Open Board files still import exactly as before', () async {
      final r = await BoardImporter().import(
          bytes: File('docs/samples/sample-board.obz').readAsBytesSync(),
          images: MemoryImageSink());
      expect(r.words.length, 12);
      expect(r.imagesCount, 12);
    });
  });
}
