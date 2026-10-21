import 'package:shared_preferences/shared_preferences.dart';

/// How the user is used to expressing themselves on their board (21.10):
/// some boards say every button the moment it is pressed, others collect
/// words in a message window and speak on "send". The screen that rides
/// on their board follows the pattern they know; a partner sets it once.
enum BoardExpressionMode {
  /// Every word pressed is a message — sent to the companion at once.
  immediate,

  /// Words gather in a tray; "שלח" sends them as one message.
  tray,
}

class BoardModePrefs {
  static const _key = 'creative_aac.board_expression_mode.v1';

  Future<BoardExpressionMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == 'tray'
        ? BoardExpressionMode.tray
        : BoardExpressionMode.immediate;
  }

  Future<void> save(BoardExpressionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, mode == BoardExpressionMode.tray ? 'tray' : 'immediate');
  }
}
