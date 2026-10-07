import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_config.dart';
import '../l10n.dart';
import '../models.dart';
import 'local_store.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  final LocalStore store;
  AuthService(this.store);

  bool get cloudAvailable => FirebaseConfig.isConfigured;

  String _hash(String password, String salt) {
    var bytes = utf8.encode('$salt:$password');
    var digest = sha256.convert(bytes);
    for (var i = 0; i < 5000; i++) {
      digest = sha256.convert([...digest.bytes, ...utf8.encode(salt)]);
    }
    return digest.toString();
  }

  String _normUser(String u) => u.trim().toLowerCase();

  Future<Session> registerLocal(String username, String password) async {
    final u = _normUser(username);
    if (u.length < 3) throw AuthException(tr('auth.userShort'));
    if (password.length < 4) throw AuthException(tr('auth.passShort'));
    final accounts = await store.readAccounts();
    if (accounts.containsKey(u)) throw AuthException(tr('auth.userExists'));
    final salt = newId(16);
    accounts[u] = {'salt': salt, 'hash': _hash(password, salt), 'display': username.trim()};
    await store.writeAccounts(accounts);
    return Session(mode: AccountMode.local, key: u, displayName: username.trim());
  }

  Future<Session> loginLocal(String username, String password) async {
    final u = _normUser(username);
    final accounts = await store.readAccounts();
    final a = accounts[u];
    if (a == null) throw AuthException(tr('auth.userNotFound'));
    final m = Map<String, dynamic>.from(a as Map);
    if (_hash(password, m['salt'] as String) != m['hash']) {
      throw AuthException(tr('auth.wrongPass'));
    }
    return Session(
        mode: AccountMode.local, key: u, displayName: (m['display'] as String?) ?? u);
  }

  Session _fromUser(User user) => Session(
        mode: AccountMode.cloud,
        key: user.uid,
        displayName: (user.displayName?.trim().isNotEmpty ?? false)
            ? user.displayName!.trim()
            : (user.email ?? tr('auth.user')),
        email: user.email,
      );

  String _firebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return tr('auth.invalidEmail');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return tr('auth.badCredentials');
      case 'email-already-in-use':
        return tr('auth.emailInUse');
      case 'weak-password':
        return tr('auth.weakPass');
      case 'network-request-failed':
        return tr('auth.network');
      case 'operation-not-allowed':
        return tr('auth.emailDisabled');
      case 'too-many-requests':
        return tr('auth.tooMany');
      case 'user-disabled':
        return tr('auth.userDisabled');
      default:
        return tr('auth.generic', {'code': e.code});
    }
  }

  Future<Session> registerCloud(String email, String password) async {
    try {
      final c = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email.trim(), password: password);
      return _fromUser(c.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseError(e));
    }
  }

  Future<Session> loginCloud(String email, String password) async {
    try {
      final c = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email.trim(), password: password);
      return _fromUser(c.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseError(e));
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseError(e));
    }
  }

  GoogleSignIn _google() => GoogleSignIn(
        scopes: const ['email'],
        serverClientId: FirebaseConfig.googleWebClientId.isEmpty
            ? null
            : FirebaseConfig.googleWebClientId,
      );

  Future<Session> loginGoogle() async {
    try {
      final g = _google();
      final account = await g.signIn();
      if (account == null) throw AuthException(tr('auth.googleCancelled'));
      final auth = await account.authentication;
      final cred = GoogleAuthProvider.credential(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      final c = await FirebaseAuth.instance.signInWithCredential(cred);
      return _fromUser(c.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseError(e));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(tr('auth.googleFailed', {'error': e}));
    }
  }

  bool cloudSessionValid(Session s) {
    if (!cloudAvailable) return false;
    final u = FirebaseAuth.instance.currentUser;
    return u != null && u.uid == s.key;
  }

  Future<void> deleteCloudAccount() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await u.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') throw AuthException(tr('account.relogin'));
      throw AuthException(_firebaseError(e));
    }
  }

  Future<void> logout(Session? s) async {
    if (s?.mode == AccountMode.cloud && cloudAvailable) {
      try {
        await _google().signOut();
      } catch (_) {}
      await FirebaseAuth.instance.signOut();
    }
  }
}
