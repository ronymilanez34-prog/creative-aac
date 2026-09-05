/// Backend configuration.
///
/// The app runs fully offline by default (scripted demo companion, device
/// TTS). To connect the real Claude backend, deploy `functions/` and run with:
///
///   flutter run \
///     --dart-define=COMPANION_ENDPOINT=`https://europe-west1-PROJECT.cloudfunctions.net/companionTurnHttp` \
///     --dart-define=COMPANION_APP_KEY=`the APP_KEY secret`
///
/// Passing secrets via --dart-define keeps them out of source control. An
/// empty endpoint means "offline mode" everywhere.
// .trim() defends against invisible whitespace that sneaks into CI secrets
// when values are pasted from a terminal — a trailing newline in the app key
// once cost hours of 401 debugging.
final String kCompanionEndpoint =
    const String.fromEnvironment('COMPANION_ENDPOINT', defaultValue: '').trim();
final String kCompanionAppKey =
    const String.fromEnvironment('COMPANION_APP_KEY', defaultValue: '').trim();

/// CI run number baked into each build (see app-build.yml). Shown tiny on
/// the home screen so "which version is actually running here?" is a glance,
/// not a debugging session. Empty in local/dev builds.
const String kBuildStamp =
    String.fromEnvironment('BUILD_STAMP', defaultValue: '');

/// Placeholder personal profile fed to the companion until the clinician
/// calibration mode exists. Structure and examples:
/// docs/ASSESSMENT_TO_PROMPT.md.
const String kDefaultProfile = '';
