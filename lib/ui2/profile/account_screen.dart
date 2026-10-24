// account_screen.dart — Cloud account login, registration, and data backup/sync.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../cloud/account_service.dart';
import '../screens/home_screen.dart' show clockOfTs;
import '../screens/journal_compose.dart' show OsTextField;
import '../ui2.dart';
import 'profile.dart' show ProfilePhoto;

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _server = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    AccountService.instance.init();
    AccountService.instance.addListener(_onAccountChanged);
  }

  @override
  void dispose() {
    AccountService.instance.removeListener(_onAccountChanged);
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      await AccountService.instance.logIn(
        email: _email.text,
        passwordOrToken: _password.text,
        customServerUrl: _server.text.isNotEmpty ? _server.text : null,
      );
      if (mounted) {
        setState(() {
          _success = 'Successfully logged in and synced data!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      final ok = await AccountService.instance.syncNow();
      if (mounted) {
        setState(() {
          _success = ok
              ? 'Cloud backup completed successfully.'
              : 'Backup initiated. Check network connection.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final account = AccountService.instance;
    final loggedIn = account.isLoggedIn;
    final profile = account.current;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                'Cloud Account',
                sub: loggedIn ? 'Logged in & synced' : 'Log in to backup data',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  if (_error != null) ...[
                    StatusCard('Notice', _error!, icon: LucideIcons.circleAlert),
                    const SizedBox(height: S.x3),
                  ],
                  if (_success != null) ...[
                    StatusCard('Success', _success!, icon: LucideIcons.badgeCheck),
                    const SizedBox(height: S.x3),
                  ],
                  if (loggedIn && profile != null) ...[
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // The profile picture set on Profile, the
                              // same one every tab's avatar shows.
                              ValueListenableBuilder<String?>(
                                valueListenable: ProfilePhoto.path,
                                builder: (_, photo, _) => photo != null
                                    ? CircleAvatar(
                                        radius: 24,
                                        backgroundImage: FileImage(File(photo)),
                                        backgroundColor: p.wash(C.blue),
                                      )
                                    : CircleAvatar(
                                  radius: 24,
                                  backgroundColor: p.wash(C.blue),
                                  child: Icon(
                                    LucideIcons.user,
                                    color: C.blue,
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: S.x3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (profile.displayName != null && profile.displayName!.isNotEmpty) ...[
                                      Text(
                                        profile.displayName!,
                                        style: F.body.copyWith(
                                          color: p.ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        profile.email,
                                        style: F.cap.copyWith(color: p.ink2),
                                      ),
                                    ] else ...[
                                      Text(
                                        profile.email,
                                        style: F.body.copyWith(
                                          color: p.ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: S.x1),
                                    Pill(
                                      'Connected & Active',
                                      C.green,
                                      icon: LucideIcons.check,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: S.x4),
                          Divider(color: p.line),
                          const SizedBox(height: S.x2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Last cloud sync', style: F.cap.copyWith(color: p.ink3)),
                              Text(
                                profile.lastSyncTime != null
                                    ? clockOfTs(profile.lastSyncTime!.millisecondsSinceEpoch ~/ 1000)
                                    : 'Never',
                                style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: S.x2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Server', style: F.cap.copyWith(color: p.ink3)),
                              Text(
                                profile.serverUrl ?? 'Locus Cloud',
                                style: F.cap.copyWith(color: p.ink2),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: S.x4),
                    Surface(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Auto-sync data', style: F.body.copyWith(fontWeight: FontWeight.w600, color: p.ink)),
                              Text('Upload backups periodically', style: F.cap.copyWith(color: p.ink3)),
                            ],
                          ),
                          Switch.adaptive(
                            value: profile.autoSync,
                            onChanged: (v) => account.setAutoSync(v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: S.x4),
                    BigButton(
                      account.isSyncing || _loading ? 'Backing up...' : 'Back up data to cloud now',
                      icon: LucideIcons.cloudUpload,
                      color: C.blue,
                      soft: true,
                      onTap: account.isSyncing || _loading ? null : _sync,
                    ),
                    const SizedBox(height: S.x3),
                    BigButton(
                      'Log out',
                      icon: LucideIcons.logOut,
                      color: C.red,
                      soft: true,
                      onTap: () async {
                        await account.logOut();
                        if (mounted) {
                          setState(() {
                            _success = 'Logged out.';
                          });
                        }
                      },
                    ),
                  ] else ...[
                    StatusCard(
                      'Sync Your Health Data',
                      'Sign in to automatically back up your health metrics, sleep analyses, and Whoop history to the cloud.',
                      icon: LucideIcons.cloud,
                    ),
                    const SizedBox(height: S.x4),
                    OsTextField(
                      controller: _email,
                      label: 'Email address',
                      hint: 'you@example.com',
                      keyboard: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: S.x3),
                    OsTextField(
                      controller: _password,
                      label: 'Password or Access Key',
                      hint: '••••••••',
                    ),
                    const SizedBox(height: S.x3),
                    OsTextField(
                      controller: _server,
                      label: 'Cloud Endpoint (optional)',
                      hint: 'https://cloud.openstrap.org',
                    ),
                    const SizedBox(height: S.x4),
                    BigButton(
                      _loading ? 'Signing in...' : 'Sign In with Email',
                      icon: LucideIcons.logIn,
                      color: C.blue,
                      onTap: _loading ? null : _login,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
