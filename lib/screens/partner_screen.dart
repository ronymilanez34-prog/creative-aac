import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/profile.dart';
import '../services/backup.dart' as backup;
import '../services/interaction_log.dart';
import '../services/profile_store.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// Partner/clinician mode: edit the personal profile (including the script
/// library) and review usage data. This is the "supporter" surface — the
/// user-facing creation experience never shows any of it.
///
/// Access model (Amendment 18 spirit): the profile belongs to the user;
/// partners see and suggest. Every save is local to the device.
class PartnerScreen extends StatefulWidget {
  const PartnerScreen({super.key});

  @override
  State<PartnerScreen> createState() => _PartnerScreenState();
}

class _PartnerScreenState extends State<PartnerScreen> {
  final ProfileStore _store = ProfileStore();
  final InteractionLog _log = InteractionLog();

  final _name = TextEditingController();
  final _level = TextEditingController();
  final _loves = TextEditingController();
  final _triggers = TextEditingController();
  final _calming = TextEditingController();
  final _notes = TextEditingController();
  List<ScriptEntry> _scripts = [];

  bool _loaded = false;
  bool _saved = false;

  // Log reads are held in state so rebuilds (typing, saving, editing
  // scripts) don't re-decode the whole stored log on every frame.
  late Future<Map<String, int>> _desireFuture;
  late Future<UsageStats> _usageFuture;
  late Future<Map<String, int>> _chipFuture;

  /// Quick-fires and safeguard flags since the partner's last visit —
  /// captured once on entry, then the visit is marked as the new baseline.
  SinceReview? _sinceReview;

  @override
  void initState() {
    super.initState();
    _desireFuture = _log.freeTextCounts();
    _usageFuture = _log.usageStats();
    _chipFuture = _log.chipChoiceCounts();
    _log.sinceLastReview().then((s) {
      if (!mounted) return;
      setState(() => _sinceReview = s);
      // Mark reviewed only after the summary is actually on screen.
      _log.markReviewed();
    });
    _load();
  }

  Future<void> _load() async {
    final p = await _store.load();
    if (!mounted) return;
    setState(() {
      _name.text = p.name;
      _level.text = p.level;
      _loves.text = p.loves.join(', ');
      _triggers.text = p.triggers.join(', ');
      _calming.text = p.calming.join(', ');
      _notes.text = p.notes;
      _scripts = List.of(p.scripts);
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _level.dispose();
    _loves.dispose();
    _triggers.dispose();
    _calming.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> _split(String s) => s
      .split(RegExp(r'[,،]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final profile = UserProfile(
      name: _name.text.trim(),
      level: _level.text.trim(),
      loves: _split(_loves.text),
      triggers: _split(_triggers.text),
      calming: _split(_calming.text),
      scripts: _scripts,
      notes: _notes.text.trim(),
    );
    await _store.save(profile);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הפרופיל נשמר במכשיר 💾')),
    );
  }

  Future<void> _addScript({String? prefill}) async {
    final expression = TextEditingController(text: prefill ?? '');
    final meaning = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ביטוי אישי חדש'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: expression,
                decoration: const InputDecoration(
                  labelText: 'הביטוי (ציטוט, סקריפט, צירוף)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: meaning,
                decoration: const InputDecoration(
                  labelText: 'המשמעות האישית שלו',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('הוסף'),
            ),
          ],
        ),
      ),
    );
    if (added == true &&
        expression.text.trim().isNotEmpty &&
        meaning.text.trim().isNotEmpty) {
      setState(() {
        _scripts.add(ScriptEntry(
          expression: expression.text.trim(),
          meaning: meaning.text.trim(),
        ));
        _saved = false;
      });
    }
    expression.dispose();
    meaning.dispose();
  }

  Future<void> _exportLog() async {
    final json = await _log.export();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הלוג הועתק — אפשר להדביק לקובץ/מייל 📋')),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// "The voice doesn't work" must never be a guessing game: speaks a real
  /// test sentence from inside this tap and shows what the engine reports
  /// — a screenshot of the dialog is a complete remote bug report.
  Future<void> _voiceCheck() async {
    final speech = Speech();
    final report = await speech.diagnose();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('בדיקת קול 🔊'),
          content: Text(report, style: const TextStyle(fontSize: 15)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('סגירה'),
            ),
          ],
        ),
      ),
    );
    speech.dispose();
  }

  /// Everything on the device into one file: profile, stories with their
  /// pictures, imported board, log. The whole world in browser storage is
  /// one cleared history away from gone — this is the door out.
  Future<void> _backupToFile() async {
    try {
      final json = await backup.exportAll();
      final bytes = Uint8List.fromList(utf8.encode(json));
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name =
          'creative-aac-backup-${now.year}-${two(now.month)}-${two(now.day)}.json';
      final saved = await FilePicker.platform.saveFile(
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      // On some platforms cancelling returns null; the web download path
      // may too — phrase the toast so neither case lies.
      _toast(saved == null
          ? 'אם נפתח חלון שמירה ובוטל — לא נשמר; אחרת חפשו את הקובץ בהורדות 💾'
          : 'הגיבוי נשמר 💾');
    } catch (e) {
      _toast('הגיבוי נכשל: $e');
    }
  }

  /// Restore replaces EVERYTHING on the device with the chosen file — the
  /// file is validated before anything is touched, and the person confirms
  /// with the date the backup was made.
  Future<void> _restoreFromFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final data = picked?.files.single.bytes;
      if (data == null) return;
      final raw = utf8.decode(data);
      // Validate first — a bad file must never wipe a device.
      backup.decodeSnapshot(raw);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('לשחזר מהגיבוי?'),
            content: const Text(
              'השחזור יחליף את כל מה שנמצא עכשיו במכשיר — הפרופיל, '
              'הסיפורים, לוח המילים והלוג — במה שבקובץ.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('לשחזר'),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
      final count = await backup.restoreAll(raw);
      _toast('שוחזר ($count פריטים) ✅');
      if (!mounted) return;
      // The screen shows restored data from here on.
      setState(() => _loaded = false);
      _desireFuture = _log.freeTextCounts();
      _usageFuture = _log.usageStats();
      _chipFuture = _log.chipChoiceCounts();
      await _load();
    } on FormatException catch (e) {
      _toast('הקובץ לא שוחזר — ${e.message}');
    } catch (e) {
      _toast('השחזור נכשל: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('מצב מלווה'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Distress first: what happened since the last visit must
                  // be the first thing a partner sees — this card is the
                  // minimal escalation path behind the quick bar and the
                  // companion's safeguard flag.
                  if (_sinceReview != null && !_sinceReview!.isEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFB25400), width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⚠️ מאז הביקור האחרון שלכם',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB25400),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (_sinceReview!.quickFires.isNotEmpty)
                                'לחיצות חירום (${_sinceReview!.quickFires.length}): '
                                    '${_sinceReview!.quickFires.join(' · ')}',
                              if (_sinceReview!.safeguards > 0)
                                'השיחה עם בן-הלוויה סימנה מצוקה '
                                    '${_sinceReview!.safeguards} פעמים — כדאי לדבר על זה יחד.',
                            ].join('\n'),
                            style:
                                const TextStyle(fontSize: 15, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  const _SectionTitle('הפרופיל האישי'),
                  const Text(
                    'מה שנכתב כאן מוזן ל-AI בכל תור, ונשמר על המכשיר בלבד. '
                    'הפרופיל שייך למשתמש — אתם רואים ומציעים.',
                    style: TextStyle(color: AppColors.textSoft),
                  ),
                  const SizedBox(height: 12),
                  _Field(controller: _name, label: 'שם'),
                  _Field(
                    controller: _level,
                    label: 'משלב ורמה (למשל: מילים בודדות וסמלים)',
                  ),
                  _Field(
                    controller: _loves,
                    label: 'תחומי עניין (מופרדים בפסיק)',
                  ),
                  _Field(
                    controller: _triggers,
                    label: 'להימנע — טריגרים (מופרדים בפסיק)',
                  ),
                  _Field(
                    controller: _calming,
                    label: 'מרגיע (מופרד בפסיק)',
                  ),
                  const SizedBox(height: 16),
                  const _SectionTitle('ספריית הביטויים האישיים'),
                  const Text(
                    'ציטוטים וסקריפטים עם המשמעות שלהם. ה-AI מכבד ומשלב — '
                    'לעולם לא "מתקן".',
                    style: TextStyle(color: AppColors.textSoft),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _scripts.length; i++)
                    Card(
                      color: AppColors.surface,
                      child: ListTile(
                        title: Text('"${_scripts[i].expression}"'),
                        subtitle: Text(_scripts[i].meaning),
                        trailing: IconButton(
                          tooltip: 'הסר',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() {
                            _scripts.removeAt(i);
                            _saved = false;
                          }),
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _addScript,
                    icon: const Icon(Icons.add),
                    label: const Text('הוספת ביטוי'),
                  ),
                  const SizedBox(height: 8),
                  _Field(controller: _notes, label: 'הערות חופשיות', lines: 3),
                  const SizedBox(height: 12),
                  BigButton(
                    label: _saved ? 'נשמר ✓' : 'שמירת הפרופיל',
                    emoji: _saved ? null : '💾',
                    onTap: _save,
                  ),
                  const SizedBox(height: 28),
                  const _SectionTitle('שבילי רצון'),
                  const Text(
                    'ביטויים שהמשתמש הקליד שוב ושוב — שביל שנשחק בדשא. '
                    'אפשר "לסלול" אותו: להוסיף לספריית הביטויים בלחיצה.',
                    style: TextStyle(color: AppColors.textSoft),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<Map<String, int>>(
                    future: _desireFuture,
                    builder: (context, snap) {
                      final counts = snap.data ?? const {};
                      final repeated = counts.entries
                          .where((e) => e.value >= 2)
                          .toList()
                        ..sort((a, b) => b.value.compareTo(a.value));
                      if (repeated.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            'עדיין אין ביטויים חוזרים.',
                            style: TextStyle(color: AppColors.textSoft),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final e in repeated.take(5))
                            Card(
                              color: AppColors.surface,
                              child: ListTile(
                                title: Text('"${e.key}"'),
                                subtitle: Text('הוקלד ${e.value} פעמים'),
                                trailing: IconButton(
                                  tooltip: 'הוספה לספריית הביטויים',
                                  icon: const Icon(Icons.add_road),
                                  onPressed: () =>
                                      _addScript(prefill: e.key),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('השערות מהשימוש'),
                  const Text(
                    'ראיה, לא משמעות: מה שנבחר שוב ושוב מוצג כהשערה — '
                    'שום דבר לא נכנס לפרופיל בלי אישור שלכם.',
                    style: TextStyle(color: AppColors.textSoft),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<Map<String, int>>(
                    future: _chipFuture,
                    builder: (context, snap) {
                      final counts = snap.data ?? const {};
                      final repeated = counts.entries
                          .where((e) =>
                              e.value >= 3 &&
                              !_loves.text.contains(e.key))
                          .toList()
                        ..sort((a, b) => b.value.compareTo(a.value));
                      if (repeated.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            'עדיין אין בחירות חוזרות מובהקות.',
                            style: TextStyle(color: AppColors.textSoft),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final e in repeated.take(5))
                            Card(
                              color: AppColors.surface,
                              child: ListTile(
                                title: Text('"${e.key}"'),
                                subtitle: Text(
                                    'נבחר ${e.value} פעמים — אולי תחום עניין?'),
                                trailing: IconButton(
                                  tooltip: 'הוספה לתחומי העניין',
                                  icon: const Icon(Icons.favorite_border),
                                  onPressed: () => setState(() {
                                    final cur = _loves.text.trim();
                                    _loves.text = cur.isEmpty
                                        ? e.key
                                        : '$cur, ${e.key}';
                                    _saved = false;
                                  }),
                                ),
                              ),
                            ),
                          const Padding(
                            padding: EdgeInsets.only(top: 2, bottom: 4),
                            child: Text(
                              'אחרי הוספה — לחצו "שמירת הפרופיל" למעלה כדי שההשערה תיכנס בפועל.',
                              style: TextStyle(
                                  color: AppColors.textSoft, fontSize: 13),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('נתוני שימוש (לקלינאית)'),
                  _UsageSummary(future: _usageFuture),
                  const SizedBox(height: 8),
                  BigButton(
                    label: 'העתקת הלוג המלא',
                    emoji: '📋',
                    color: AppColors.accent,
                    onTap: _exportLog,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'הנתונים נשארים על המכשיר ומשמשים ללמידה בלבד — לעולם לא '
                    'להערכה של המשתמש או כתגובה ללחיצות חירום.',
                    style: TextStyle(color: AppColors.textSoft, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('קול'),
                  BigButton(
                    label: 'בדיקת קול',
                    emoji: '🔊',
                    color: AppColors.accent,
                    onTap: _voiceCheck,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'לוחצים — אמור להישמע משפט. הדו"ח שמופיע מסביר מה המנוע '
                    'מדווח; צילום מסך שלו הוא דיווח תקלה מלא.',
                    style: TextStyle(color: AppColors.textSoft, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('גיבוי ושחזור'),
                  const Text(
                    'כל העולם של המשתמש — הפרופיל, הסיפורים והתמונות, לוח '
                    'המילים והלוג — נשמר בדפדפן הזה בלבד. ניקוי היסטוריה או '
                    'החלפת מכשיר מוחקים הכול. גבו לקובץ אחרי כל עבודה '
                    'משמעותית.',
                    style: TextStyle(color: AppColors.textSoft, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  BigButton(
                    label: 'גיבוי הכול לקובץ',
                    emoji: '💾',
                    onTap: _backupToFile,
                  ),
                  const SizedBox(height: 8),
                  BigButton(
                    label: 'שחזור מקובץ גיבוי',
                    emoji: '📂',
                    color: AppColors.accent,
                    onTap: _restoreFromFile,
                  ),
                ],
              ),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, this.lines = 1});

  final TextEditingController controller;
  final String label;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// Small live summary from the on-device interaction log: totals, quick-fire
/// count, and the position-of-selection distribution (the position-bias
/// signal — choices tracking screen location rather than content).
class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.future});

  final Future<UsageStats> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsageStats>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 40);
        final stats = snap.data!;
        final counts = stats.positionCounts;
        final positions = (counts.keys.toList()..sort())
            .map((k) => 'מיקום ${k + 1}: ${counts[k]}')
            .join(' · ');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'בחירות: ${stats.selections} · לחיצות חירום: ${stats.quickFires}\n'
            'התפלגות מיקומי בחירה: ${positions.isEmpty ? 'אין עדיין' : positions}\n'
            'התפלגות מוטה מאוד למיקום אחד = ייתכן שהבחירה עוקבת אחרי מקום '
            'על המסך ולא אחרי תוכן.',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        );
      },
    );
  }
}
