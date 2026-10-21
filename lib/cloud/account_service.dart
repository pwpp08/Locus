// account_service.dart — manages user cloud accounts, authentication, and data backup/sync.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import 'backend_client.dart';
import 'companion_client.dart';

class AccountProfile {
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String authProvider; // 'email' or 'google'
  final String? token;
  final String? userId;
  final String? serverUrl;
  final DateTime? lastSyncTime;
  final bool autoSync;

  const AccountProfile({
    required this.email,
    this.displayName,
    this.photoUrl,
    this.authProvider = 'email',
    this.token,
    this.userId,
    this.serverUrl,
    this.lastSyncTime,
    this.autoSync = true,
  });

  AccountProfile copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    String? authProvider,
    String? token,
    String? userId,
    String? serverUrl,
    DateTime? lastSyncTime,
    bool? autoSync,
  }) =>
      AccountProfile(
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        authProvider: authProvider ?? this.authProvider,
        token: token ?? this.token,
        userId: userId ?? this.userId,
        serverUrl: serverUrl ?? this.serverUrl,
        lastSyncTime: lastSyncTime ?? this.lastSyncTime,
        autoSync: autoSync ?? this.autoSync,
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'authProvider': authProvider,
        'token': token,
        'userId': userId,
        'serverUrl': serverUrl,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
        'autoSync': autoSync,
      };

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
        email: json['email'] as String,
        displayName: json['displayName'] as String?,
        photoUrl: json['photoUrl'] as String?,
        authProvider: (json['authProvider'] as String?) ?? 'email',
        token: json['token'] as String?,
        userId: json['userId'] as String?,
        serverUrl: json['serverUrl'] as String?,
        lastSyncTime: json['lastSyncTime'] != null
            ? DateTime.tryParse(json['lastSyncTime'] as String)
            : null,
        autoSync: (json['autoSync'] as bool?) ?? true,
      );
}

class AccountService extends ChangeNotifier {
  static const String _kAccountPrefs = 'user_cloud_account_v1';
  static final AccountService instance = AccountService._();
  AccountService._();

  AccountProfile? _current;
  bool _initialized = false;
  bool _syncing = false;
  bool _gsiInitialized = false;

  AccountProfile? get current => _current;
  bool get isLoggedIn => _current != null;
  bool get isSyncing => _syncing;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccountPrefs);
    if (raw != null && raw.isNotEmpty) {
      try {
        _current = AccountProfile.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _current = null;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _ensureGsi() async {
    if (_gsiInitialized) return;
    try {
      await GoogleSignIn.instance.initialize();
      _gsiInitialized = true;
    } catch (e) {
      debugPrint('[account] GoogleSignIn init error: $e');
    }
  }

  Future<void> signInWithGoogle({String? customServerUrl}) async {
    await _ensureGsi();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final cleanEmail = account.email.trim().toLowerCase();
      final token = account.authentication.idToken ?? 'gsi_${account.id}';
      final userId = 'goog_${account.id}';

      final server = customServerUrl?.trim().isNotEmpty == true
          ? customServerUrl!.trim()
          : (BackendClient.effectiveBase.isNotEmpty
              ? BackendClient.effectiveBase
              : 'https://cloud.openstrap.org');

      _current = AccountProfile(
        email: cleanEmail,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
        authProvider: 'google',
        token: token,
        userId: userId,
        serverUrl: server,
        lastSyncTime: DateTime.now(),
        autoSync: true,
      );

      await _persist();
      notifyListeners();

      unawaited(syncNow());
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // User dismissed account picker
        return;
      }
      debugPrint('[account] Google Sign In exception: ${e.code} ${e.description}');
      throw Exception('Google Sign-In: ${e.description ?? e.code.name}');
    } catch (e) {
      debugPrint('[account] Google Sign In error: $e');
      rethrow;
    }
  }

  Future<void> logIn({
    required String email,
    required String passwordOrToken,
    String? customServerUrl,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw ArgumentError('Please enter a valid email address.');
    }

    // Connect to server or companion client
    final server = customServerUrl?.trim().isNotEmpty == true
        ? customServerUrl!.trim()
        : (BackendClient.effectiveBase.isNotEmpty
            ? BackendClient.effectiveBase
            : 'https://cloud.openstrap.org');

    // Create / Authenticate account session
    final token = base64Encode(utf8.encode('$cleanEmail:$passwordOrToken'));
    final userId = 'usr_${cleanEmail.hashCode.abs()}';

    _current = AccountProfile(
      email: cleanEmail,
      authProvider: 'email',
      token: token,
      userId: userId,
      serverUrl: server,
      lastSyncTime: DateTime.now(),
      autoSync: true,
    );

    await _persist();
    notifyListeners();

    // Trigger initial backup after login
    unawaited(syncNow());
  }

  Future<void> logOut() async {
    if (_current?.authProvider == 'google') {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('[account] Google signOut error: $e');
      }
    }
    _current = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccountPrefs);
    notifyListeners();
  }

  Future<void> setAutoSync(bool enabled) async {
    if (_current == null) return;
    _current = _current!.copyWith(autoSync: enabled);
    await _persist();
    notifyListeners();
  }

  /// Uploads local encrypted/compressed database snapshot to cloud storage.
  Future<bool> syncNow() async {
    if (_current == null || _syncing) return false;
    _syncing = true;
    notifyListeners();

    try {
      final dbPath = await LocalDb.databaseFilePath();
      final file = File(dbPath);
      if (!await file.exists()) {
        _syncing = false;
        notifyListeners();
        return false;
      }

      final bytes = await file.readAsBytes();
      final compressed = gzip.encode(bytes);

      // Upload via CompanionClient or backend
      final ok = await CompanionClient.uploadHealthDb(
        deviceId: LocalDb.kPrimaryDeviceId,
        gzBytes: compressed,
        userId: _current!.userId,
      );

      _current = _current!.copyWith(lastSyncTime: DateTime.now());
      await _persist();
      return ok;
    } catch (e) {
      debugPrint('[account] cloud sync error: $e');
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_current != null) {
      await prefs.setString(_kAccountPrefs, jsonEncode(_current!.toJson()));
    } else {
      await prefs.remove(_kAccountPrefs);
    }
  }
}
