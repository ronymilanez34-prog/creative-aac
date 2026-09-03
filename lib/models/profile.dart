import 'dart:convert';

/// The personal profile — layer 2 of the learning architecture (see
/// docs/ASSESSMENT_TO_PROMPT.md). Owned by the user; edited with a partner
/// or clinician in partner mode; rendered into the {{PROFILE}} slot of the
/// companion prompt on every turn. Stored only on this device.
class ScriptEntry {
  const ScriptEntry({required this.expression, required this.meaning});

  /// A whole phrase/quote the person uses (echolalia, script, idiolect).
  final String expression;

  /// Its personal meaning — respected and woven in, never "corrected".
  final String meaning;

  Map<String, dynamic> toJson() =>
      {'expression': expression, 'meaning': meaning};

  factory ScriptEntry.fromJson(Map<String, dynamic> j) => ScriptEntry(
        expression: (j['expression'] ?? '').toString(),
        meaning: (j['meaning'] ?? '').toString(),
      );
}

class UserProfile {
  UserProfile({
    this.name = '',
    this.level = '',
    this.loves = const [],
    this.triggers = const [],
    this.calming = const [],
    this.scripts = const [],
    this.notes = '',
  });

  final String name;

  /// Communication level / register in the partner's words
  /// (e.g. "מילים בודדות וסמלים", "משפטים מלאים, בלי שפה ילדותית").
  final String level;

  /// Interests — the door into their world; one option per turn routes
  /// through these (wide walls).
  final List<String> loves;

  /// Topics/stimuli to avoid.
  final List<String> triggers;

  /// What calms and regulates.
  final List<String> calming;

  /// The script library — personal expressions with their meanings.
  final List<ScriptEntry> scripts;

  /// Free clinician/partner notes.
  final String notes;

  bool get isEmpty =>
      name.isEmpty &&
      level.isEmpty &&
      loves.isEmpty &&
      triggers.isEmpty &&
      calming.isEmpty &&
      scripts.isEmpty &&
      notes.isEmpty;

  /// Renders the {{PROFILE}} block for the companion prompt. Hebrew, short
  /// lines, only non-empty fields.
  String toPromptText() {
    if (isEmpty) return '';
    final b = StringBuffer();
    if (name.isNotEmpty) b.writeln('שם: $name.');
    if (level.isNotEmpty) b.writeln('משלב ורמה: $level.');
    if (loves.isNotEmpty) b.writeln('תחומי עניין (שלב אחד מהם כאפשרות בכל תור): ${loves.join(', ')}.');
    if (triggers.isNotEmpty) b.writeln('להימנע (טריגרים): ${triggers.join(', ')}.');
    if (calming.isNotEmpty) b.writeln('מרגיע: ${calming.join(', ')}.');
    if (scripts.isNotEmpty) {
      b.writeln('ביטויים אישיים — שפה, לא שגיאה. זהה, כבד ושלב; לעולם אל תתקן:');
      for (final s in scripts) {
        b.writeln('- "${s.expression}" ← ${s.meaning}');
      }
    }
    if (notes.isNotEmpty) b.writeln('הערות מהמלווה: $notes');
    return b.toString().trim();
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'level': level,
        'loves': loves,
        'triggers': triggers,
        'calming': calming,
        'scripts': scripts.map((s) => s.toJson()).toList(),
        'notes': notes,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name: (j['name'] ?? '').toString(),
        level: (j['level'] ?? '').toString(),
        loves: _strings(j['loves']),
        triggers: _strings(j['triggers']),
        calming: _strings(j['calming']),
        scripts: (j['scripts'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ScriptEntry.fromJson)
            .toList(),
        notes: (j['notes'] ?? '').toString(),
      );

  static List<String> _strings(Object? v) => (v as List? ?? const [])
      .map((e) => e.toString())
      .where((s) => s.trim().isNotEmpty)
      .toList();

  String encode() => jsonEncode(toJson());

  factory UserProfile.decode(String raw) {
    // A corrupt or wrong-typed stored profile must never take down the main
    // creation flow — any failure falls back to an empty profile.
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return UserProfile.fromJson(j);
    } catch (_) {
      // fall through to empty profile
    }
    return UserProfile();
  }
}
