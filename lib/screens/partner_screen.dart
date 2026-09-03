import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/profile.dart';
import '../services/interaction_log.dart';
import '../services/profile_store.dart';
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

  @override
  void initState() {
    super.initState();
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

  Future<void> _addScript() async {
    final expression = TextEditingController();
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
                  const _SectionTitle('נתוני שימוש (לקלינאית)'),
                  _UsageSummary(log: _log),
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
  const _UsageSummary({required this.log});

  final InteractionLog log;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: log.entries(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 40);
        final entries = snap.data!;
        final selections =
            entries.where((e) => e['type'] == 'selection').length;
        final quickFires =
            entries.where((e) => e['type'] == 'quickfire').length;
        final counts = <int, int>{};
        for (final e in entries) {
          if (e['type'] == 'selection' && e['kind'] == 'chip') {
            final i = e['index'];
            if (i is int && i >= 0) counts[i] = (counts[i] ?? 0) + 1;
          }
        }
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
            'בחירות: $selections · לחיצות חירום: $quickFires\n'
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
