/// Backend configuration.
///
/// The app runs fully offline by default (scripted demo companion, device
/// TTS). To connect the real Claude backend, deploy `functions/` and run with:
///
///   flutter run \
///     --dart-define=COMPANION_ENDPOINT=https://europe-west1-<project>.cloudfunctions.net/companionTurnHttp \
///     --dart-define=COMPANION_APP_KEY=<the APP_KEY secret>
///
/// Passing secrets via --dart-define keeps them out of source control. An
/// empty endpoint means "offline mode" everywhere.
const String kCompanionEndpoint =
    String.fromEnvironment('COMPANION_ENDPOINT', defaultValue: '');
const String kCompanionAppKey =
    String.fromEnvironment('COMPANION_APP_KEY', defaultValue: '');

/// Placeholder personal profile fed to the companion until the clinician
/// calibration mode exists. Structure and examples:
/// docs/ASSESSMENT_TO_PROMPT.md.
const String kDefaultProfile = '';
