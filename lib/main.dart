import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/lexicon_store.dart';
import 'theme.dart';

void main() {
  runApp(const CreativeAacApp());
  // Warms the voice registry: adopted words that carry the creator's
  // recorded voice must sound right from the very first tap, on any
  // screen, without that screen loading the lexicon itself.
  LexiconStore().load();
}

/// Creative Alternative Communication — a calm, autism-friendly tool for
/// co-creating stories (and later games, apps and more) together with AI.
///
/// The whole UI is right-to-left Hebrew. We force [TextDirection.rtl] via the
/// app's [builder] so every screen is correctly laid out without needing the
/// intl localization packages.
class CreativeAacApp extends StatelessWidget {
  const CreativeAacApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'תקשורת חלופית יוצרת',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}
