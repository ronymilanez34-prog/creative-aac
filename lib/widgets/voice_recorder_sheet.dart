import 'dart:async';

import 'package:flutter/material.dart';

import '../services/voice_notes.dart';
import '../theme.dart';
import 'big_button.dart';

/// The one recording flow, everywhere a word gets its owner's voice:
/// opens already recording (the tap that opened it is the gesture the
/// browser needs for the microphone), one big stop button, then a preview
/// the person approves — nothing is kept without their "טוב לי".
///
/// Returns the clip as an audio data URI, or null (cancelled / failed).
Future<String?> showVoiceRecorderSheet(BuildContext context,
    {required String word}) {
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _VoiceRecorderSheet(word: word),
    ),
  );
}

enum _Phase { starting, recording, preview, failed }

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet({required this.word});

  final String word;

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  _Phase _phase = _Phase.starting;
  String _clip = '';
  int _seconds = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Swiped/backed out mid-recording: nothing is kept.
    if (VoiceNotes.isRecording) VoiceNotes.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final ok = await VoiceNotes.start();
    if (!mounted) return;
    if (!ok) {
      setState(() => _phase = _Phase.failed);
      return;
    }
    setState(() {
      _phase = _Phase.recording;
      _seconds = 0;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds++);
      // The clip is a word, not a story — stop by itself at the cap so
      // a missed tap can't fill the storage.
      if (_seconds >= kMaxVoiceSeconds) _finish();
    });
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    final clip = await VoiceNotes.stop();
    if (!mounted) return;
    if (clip == null) {
      setState(() => _phase = _Phase.failed);
      return;
    }
    setState(() {
      _clip = clip;
      _phase = _Phase.preview;
    });
    // Hearing yourself right away is the preview — no extra tap needed.
    VoiceNotes.play(clip);
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await VoiceNotes.cancel();
    await VoiceNotes.stopPlayback();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: switch (_phase) {
            _Phase.starting => [
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                const Text('פותחים את המיקרופון…',
                    style: TextStyle(fontSize: 18)),
                const SizedBox(height: 12),
                TextButton(onPressed: _cancel, child: const Text('ביטול')),
              ],
            _Phase.recording => [
                Text(
                  '🔴 מקליטים את «${widget.word}»',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'אמרו את המילה בקול שלכם ($_seconds/$kMaxVoiceSeconds)',
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.textSoft),
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: 'סיימתי',
                  emoji: '✅',
                  onTap: _finish,
                ),
                TextButton(onPressed: _cancel, child: const Text('ביטול')),
              ],
            _Phase.preview => [
                Text(
                  'ככה נשמעת «${widget.word}» בקול שלכם',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: 'לשמוע שוב',
                  emoji: '🔊',
                  color: AppColors.accent,
                  onTap: () => VoiceNotes.play(_clip),
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'טוב לי — לשמור את הקול',
                  emoji: '💛',
                  onTap: () {
                    VoiceNotes.stopPlayback();
                    Navigator.of(context).pop(_clip);
                  },
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'להקליט עוד פעם',
                  emoji: '🔄',
                  color: AppColors.textSoft,
                  onTap: () {
                    VoiceNotes.stopPlayback();
                    setState(() => _phase = _Phase.starting);
                    _begin();
                  },
                ),
                TextButton(onPressed: _cancel, child: const Text('ביטול')),
              ],
            _Phase.failed => [
                const Text('🎤', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 8),
                const Text(
                  'ההקלטה לא הצליחה הפעם',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'אולי הדפדפן לא נתן גישה למיקרופון.\n'
                  'אפשר לאשר גישה ולנסות שוב — ובינתיים הקול הרגיל ממשיך לעבוד.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 16, color: AppColors.textSoft),
                ),
                const SizedBox(height: 14),
                BigButton(
                  label: 'לנסות שוב',
                  emoji: '🔄',
                  onTap: () {
                    setState(() => _phase = _Phase.starting);
                    _begin();
                  },
                ),
                TextButton(onPressed: _cancel, child: const Text('סגירה')),
              ],
          },
        ),
      ),
    );
  }
}
