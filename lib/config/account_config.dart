/// Settings for Pro accounts (Google Sign-In, Firebase, Play subscription).
///
/// One-time setup, in order:
///  1. Firebase console → create project → add Android app with package
///     `com.attendance_flow.myapp`. Add BOTH SHA-1 fingerprints: your upload
///     key and the Play App Signing key (Play Console → Setup → App signing).
///  2. Firebase console → Authentication → Sign-in method → enable Google.
///  3. Run `flutterfire configure` (see lib/firebase_options.dart).
///  4. Google Cloud console → APIs & Services → Credentials → copy the
///     "Web client (auto created by Google Service)" client ID into
///     [googleServerClientId] below.
///  5. Firebase console → Firestore → create database (production mode), then
///     `firebase deploy --only firestore:rules,functions` from the repo root.
///  6. Play Console → Users and permissions → invite the Cloud Functions
///     service account (`<project-id>@appspot.gserviceaccount.com`) with
///     "View financial data" and "Manage orders and subscriptions", and enable
///     the Google Play Android Developer API on the Firebase project.
///  7. Play Console → Monetize → Monetization setup → Real-time developer
///     notifications → topic `projects/<project-id>/topics/play-rtdn`.
class AccountConfig {
  AccountConfig._();

  /// OAuth 2.0 *web* client ID from the Firebase project. Required by
  /// Google Sign-In on Android to mint an ID token Firebase Auth accepts.
  static const googleServerClientId =
      '782454370028-gi4rcv0po9bbtumceidbp8qbjiv4ghvj.apps.googleusercontent.com';

  static bool get hasServerClientId =>
      !googleServerClientId.startsWith('REPLACE_');

  static const packageName = 'com.attendance_flow.myapp';

  /// Google Play subscription center, filtered to this app's Pro plan.
  static const manageSubscriptionUrl =
      'https://play.google.com/store/account/subscriptions'
      '?sku=attendance_flow_pro&package=$packageName';

  /// Cloud Functions region. Keep in sync with functions/index.js.
  static const functionsRegion = 'europe-west1';
}
