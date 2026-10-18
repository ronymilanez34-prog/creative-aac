import 'package:creative_aac/services/hebrew_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nikud is stripped for the screen, letters and geresh stay', () {
    expect(stripNikud('הַכֶּלֶב הַשָּׁחֹר'), 'הכלב השחר');
    expect(stripNikud("צִ'יקוֹ"), "צ'יקו");
    expect(stripNikud('שלום, עולם!'), 'שלום, עולם!');
    expect(stripNikud('דג · ציפור'), 'דג · ציפור');
  });
}
