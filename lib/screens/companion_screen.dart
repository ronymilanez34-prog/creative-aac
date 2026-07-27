import 'package:flutter/material.dart';

import '../models/companion.dart';
import '../services/companion_service.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// The demo interface: "supported free conversation" co-creation.
///
/// Layout, top → bottom:
///  • the creation growing (the story so far),
///  • the companion's message (with read-aloud),
///  • either a confirmation prompt, or the tappable options + free-text input.
///
/// Driven by [CompanionService]; the demo passes a [MockCompanionService] so it
/// runs instantly with no backend.
class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key, required this.service});

  final CompanionService service;

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  final Speech _speech = Speech();
  final TextEditingController _input = TextEditingController();
  final ScrollController _creationScroll = ScrollController();

  final List<String> _creation = [];
  late CompanionTurn _turn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _turn = widget.service.opening();
    // Speak the opening after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak(_turn.say));
  }

  @override
  void dispose() {
    _speech.dispose();
    _input.dispose();
    _creationScroll.dispose();
    super.dispose();
  }

  void _speak(String text) => _speech.speak(text);

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    _input.clear();
    setState(() => _busy = true);

    final next = await widget.service.turn(t);
    if (!mounted) return;

    setState(() {
      if (next.creationUpdate != null && next.creationUpdate!.trim().isNotEmpty) {
        _creation.add(next.creationUpdate!.trim());
      }
      _turn = next;
      _busy = false;
    });
    _speak(next.say);
    _scrollCreationToEnd();
  }

  void _scrollCreationToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_creationScroll.hasClients) {
        _creationScroll.animateTo(
          _creationScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('בואו ניצור ביחד'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_turn.safeguard) const _SafeguardBanner(),
            _CreationCard(lines: _creation, scroll: _creationScroll),
            _CompanionBubble(text: _turn.say, onSpeak: () => _speak(_turn.say)),
            const Spacer(),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            if (_turn.needsConfirmation && _turn.confirm != null)
              _ConfirmArea(prompt: _turn.confirm!, onChoose: _send)
            else
              _OptionsArea(
                options: _turn.options,
                controller: _input,
                onChip: _send,
                onSubmit: _send,
              ),
          ],
        ),
      ),
    );
  }
}

class _CreationCard extends StatelessWidget {
  const _CreationCard({required this.lines, required this.scroll});

  final List<String> lines;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 90, maxHeight: 220),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: lines.isEmpty
          ? const Center(
              child: Text(
                'כאן ייבנה הסיפור שלך ✨',
                style: TextStyle(fontSize: 18, color: AppColors.textSoft),
              ),
            )
          : SingleChildScrollView(
              controller: scroll,
              child: Text(
                lines.join(' '),
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
    );
  }
}

class _CompanionBubble extends StatelessWidget {
  const _CompanionBubble({required this.text, required this.onSpeak});

  final String text;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🤖', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'הקרא',
            icon: const Icon(Icons.volume_up_rounded, color: AppColors.primary),
            onPressed: onSpeak,
          ),
        ],
      ),
    );
  }
}

class _OptionsArea extends StatelessWidget {
  const _OptionsArea({
    required this.options,
    required this.controller,
    required this.onChip,
    required this.onSubmit,
  });

  final List<ChipOption> options;
  final TextEditingController controller;
  final ValueChanged<String> onChip;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: options
                .map((o) => _Chip(option: o, onTap: () => onChip(o.label)))
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: onSubmit,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'או כתוב/י בעצמך…',
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onSubmit(controller.text),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.option, required this.onTap});

  final ChipOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(
                option.label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmArea extends StatelessWidget {
  const _ConfirmArea({required this.prompt, required this.onChoose});

  final ConfirmPrompt prompt;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Column(
        children: [
          Text(
            prompt.question,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 14),
          ...prompt.options.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BigButton(
                label: o,
                color: AppColors.accent,
                onTap: () => onChoose(o),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeguardBanner extends StatelessWidget {
  const _SafeguardBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3E0),
      padding: const EdgeInsets.all(12),
      child: const Text(
        'בוא נדבר על זה יחד עם מישהו שאתה סומך עליו 💛',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB25400),
        ),
      ),
    );
  }
}
