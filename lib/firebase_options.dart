// Firebase project configuration (project `attendance-flow-app`).
//
// Regenerate with, from the project root:
//
//   flutterfire configure --project=attendance-flow-app --platforms=android
//
// If the values are ever reset to `REPLACE_...` placeholders the app falls back
// to "accounts disabled" mode: everything works offline exactly as before and
// the Pro paywall skips the sign-in step.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  /// True once `flutterfire configure` has written real values.
  static bool get isConfigured =>
      !android.apiKey.startsWith('REPLACE_') &&
      !android.appId.startsWith('REPLACE_');

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDkJgyzzTVff5R9u8AgS7PYnfA65RbN3wg',
    appId: '1:782454370028:android:bcd5cf5d5aac83ee423fc9',
    messagingSenderId: '782454370028',
    projectId: 'attendance-flow-app',
    storageBucket: 'attendance-flow-app.firebasestorage.app',
  );
}
