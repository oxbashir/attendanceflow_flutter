import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/account_config.dart';
import '../firebase_options.dart';

/// Minimal identity snapshot exposed to the UI so widgets never touch
/// Firebase types directly.
class AccountUser {
  const AccountUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
}

/// Google Sign-In backed by Firebase Auth.
///
/// Accounts are optional: free users never see this. It is only invoked when
/// someone upgrades to Pro, and it stays inert when Firebase has not been
/// configured yet ([enabled] is false).
class AuthService extends ChangeNotifier {
  AuthService({this.enableFirebase = true});

  /// Set false in tests and on platforms without Firebase.
  final bool enableFirebase;

  static const cancelledMessage = 'Sign-in was cancelled.';
  static const unavailableMessage =
      'Sign-in is not available right now. Check your connection and try again.';
  static const notConfiguredMessage =
      'Accounts are not set up for this build yet.';

  bool enabled = false;
  bool busy = false;
  String? lastError;
  AccountUser? user;

  StreamSubscription<User?>? _authSub;

  bool get isSignedIn => user != null;
  String? get uid => user?.uid;

  Future<void> init() async {
    // Google Sign-In on Android needs the Web client ID to mint an ID token,
    // so without it accounts stay off (the paywall goes straight to Subscribe).
    if (!enableFirebase ||
        kIsWeb ||
        !DefaultFirebaseOptions.isConfigured ||
        !AccountConfig.hasServerClientId) {
      enabled = false;
      notifyListeners();
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await GoogleSignIn.instance.initialize(
        serverClientId: AccountConfig.googleServerClientId,
      );
      _authSub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
      _onUser(FirebaseAuth.instance.currentUser);
      enabled = true;
    } catch (e) {
      debugPrint('Auth init failed: $e');
      enabled = false;
    }
    notifyListeners();
  }

  void _onUser(User? u) {
    user = u == null
        ? null
        : AccountUser(
            uid: u.uid,
            email: u.email,
            displayName: u.displayName,
            photoUrl: u.photoURL,
          );
    notifyListeners();
  }

  /// Interactive Google Sign-In. Returns null on success, else a message.
  Future<String?> signInWithGoogle() async {
    if (!enabled) return notConfiguredMessage;
    if (busy) return null;
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google returned no ID token');
      }
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return null;
    } on GoogleSignInException catch (e) {
      lastError = e.code == GoogleSignInExceptionCode.canceled
          ? cancelledMessage
          : unavailableMessage;
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      return lastError;
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      lastError = unavailableMessage;
      return lastError;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (!enabled) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  /// Deletes the account and every cloud record via a server function so the
  /// deletion is complete and does not depend on a recent sign-in.
  Future<String?> deleteAccount() async {
    if (!enabled || !isSignedIn) return notConfiguredMessage;
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: AccountConfig.functionsRegion,
      ).httpsCallable('deleteAccount');
      await callable.call<void>();
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (_) {}
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      return null;
    } catch (e) {
      debugPrint('Delete account failed: $e');
      lastError = 'Could not delete the account. Try again later.';
      return lastError;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

class AuthScope extends InheritedNotifier<AuthService> {
  const AuthScope({
    super.key,
    required AuthService service,
    required super.child,
  }) : super(notifier: service);

  static AuthService? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;
  }
}
