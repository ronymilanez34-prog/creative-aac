import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/companion.dart';
import 'companion_service.dart';

/// Real companion: one HTTPS call per turn to the `companionTurnHttp` Cloud
/// Function (see functions/index.js), which holds the Anthropic key and the
/// system prompt. The app never talks to the Claude API directly.
class ClaudeCompanionService implements CompanionService {
  ClaudeCompanionService({
    required this.endpoint,
    this.appKey = '',
    this.profileText = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Full URL of companionTurnHttp.
  final String endpoint;

  /// Shared secret, sent as the `x-app-key` header.
  final String appKey;

  /// The personal profile block injected into the prompt ({{PROFILE}}).
  final String profileText;

  final http.Client _client;

  @override
  CompanionTurn opening() => const CompanionTurn(
        say: 'היי! מה יוצרים היום?',
        options: [
          ChipOption(emoji: '📖', label: 'סיפור'),
          ChipOption(emoji: '🎵', label: 'שיר'),
          ChipOption(emoji: '💡', label: 'רעיון'),
          ChipOption(emoji: '❓', label: 'משהו אחר'),
        ],
      );

  @override
  Future<CompanionTurn> turn(
    String userInput, {
    String creationSoFar = '',
    InputSource source = InputSource.user,
    bool lowEnergy = false,
  }) async {
    final res = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'content-type': 'application/json',
            if (appKey.isNotEmpty) 'x-app-key': appKey,
          },
          body: jsonEncode({
            'profile': profileText,
            'creationSoFar': creationSoFar,
            'userInput': userInput,
            'inputSource': source == InputSource.partner ? 'partner' : 'user',
            'lowEnergy': lowEnergy,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (res.statusCode != 200) {
      throw CompanionBackendException(res.statusCode, res.body);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw CompanionBackendException(200, 'תשובה לא צפויה מהשרת');
    }
    return CompanionTurn.fromJson(body);
  }

  @override
  void dispose() => _client.close();
}

class CompanionBackendException implements Exception {
  CompanionBackendException(this.statusCode, this.detail);

  final int statusCode;
  final String detail;

  @override
  String toString() => 'CompanionBackendException($statusCode): $detail';
}
