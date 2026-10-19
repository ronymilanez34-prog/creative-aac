import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Turns the user's composed scene into a REAL picture via the backend's
/// image-generation endpoint (same project/billing as the companion).
/// Returns raw image bytes; throws [ImagineException] with the server's
/// Hebrew message on failure.
class ImagineService {
  /// Derived from the companion endpoint — same function host.
  static String get endpoint =>
      kCompanionEndpoint.replaceFirst('companionTurnHttp', 'imagineHttp');

  /// Test seam: when set, [available] is true and [imagine] calls this
  /// instead of the network. The painter's queueing and the speculative
  /// paint are screen logic worth testing without a backend.
  static Future<Uint8List> Function(String prompt, {Uint8List? baseImage})?
      override;

  static bool get available =>
      override != null || kCompanionEndpoint.isNotEmpty;

  /// [baseImage]: when given, the backend EDITS this picture per [prompt]
  /// instead of painting a new one — the creation keeps growing instead of
  /// starting over.
  Future<Uint8List> imagine(String prompt, {Uint8List? baseImage}) async {
    final o = override;
    if (o != null) return o(prompt, baseImage: baseImage);
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'content-type': 'application/json',
            // Raw bytes back (not base64-in-JSON): a third less to pull
            // down on a tablet and nothing to decode. An older backend
            // ignores this and answers JSON, handled below.
            'accept': 'image/png, application/json',
            if (kCompanionAppKey.isNotEmpty) 'x-app-key': kCompanionAppKey,
          },
          body: jsonEncode({
            'prompt': prompt,
            if (baseImage != null) 'baseImageB64': base64Encode(baseImage),
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      String message = 'שגיאה (${res.statusCode})';
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['error'] != null) {
          message = body['error'].toString();
          // The server's technical detail is what lets us diagnose remotely.
          final detail = body['detail']?.toString() ?? '';
          if (detail.isNotEmpty) {
            message = '$message\n${detail.substring(0, detail.length > 200 ? 200 : detail.length)}';
          }
        }
      } catch (_) {}
      throw ImagineException(message, status: res.statusCode);
    }
    final type = res.headers['content-type'] ?? '';
    if (type.startsWith('image/')) {
      if (res.bodyBytes.isEmpty) {
        throw ImagineException('לא התקבלה תמונה מהשרת.');
      }
      return res.bodyBytes;
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final b64 = (body is Map ? body['imageB64'] : null)?.toString();
    if (b64 == null || b64.isEmpty) {
      throw ImagineException('לא התקבלה תמונה מהשרת.');
    }
    return base64Decode(b64);
  }
}

class ImagineException implements Exception {
  ImagineException(this.message, {this.status = 0});

  final String message;

  /// HTTP status from the backend (0 when the request never got an
  /// answer). 429 means the image model is rate-limited, not broken.
  final int status;

  bool get isBusy => status == 429;

  @override
  String toString() => message;
}
