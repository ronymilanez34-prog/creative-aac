import 'package:creative_aac/services/page_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a page card renders words and telling to a PNG', () async {
    final png = await renderPageCard(
      words: 'עץ · ציפור · כלב שחור',
      told: 'עַל רֹאשׁ הָהָר עוֹמֵד עֵץ גָּבוֹהַּ, וְצִפּוֹר מַגִּיעָה אֵלָיו.',
      title: 'הסיפור של דני',
      pageNumber: 1,
      pageCount: 2,
    );
    expect(png, isNotNull);
    expect(png!.length, greaterThan(1000));
    // PNG signature.
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('an empty page renders nothing', () async {
    expect(await renderPageCard(words: '', told: null), isNull);
  });
}
