/// Hebrew text helpers shared by the screens.
library;

/// Hebrew points and cantillation marks (U+0591–U+05C7). The model writes
/// what is SPOKEN with full nikud — the device voice reads unpointed
/// Hebrew badly (field 18.10) — and the screen shows it without, as
/// people read. Geresh/gershayim (U+05F3/U+05F4) are letters' companions
/// and stay.
final RegExp _nikud = RegExp(r'[֑-ׇ]');

String stripNikud(String text) => text.replaceAll(_nikud, '');
