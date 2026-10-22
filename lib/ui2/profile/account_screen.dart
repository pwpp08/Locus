// account_screen.dart — Cloud account login, registration, and data backup/sync.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../cloud/account_service.dart';
import '../screens/home_screen.dart' show clockOfTs;
import '../screens/journal_compose.dart' show OsTextField;
import '../ui2.dart';

const String _kGoogleLogoSvg = '''<svg viewBox="0 0 24 24" width="20" height="20">
  <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"/>
  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
</svg>''';

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

  Future<void> _loginWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      await AccountService.instance.signInWithGoogle(
        customServerUrl: _server.text.isNotEmpty ? _server.text : null,
      );
      if (mounted) {
        setState(() {
          _success = 'Successfully signed in with Google!';
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = '$e'.replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
        if (msg.contains('ApiException: 10') ||
            msg.contains('developer_error') ||
            msg.contains('clientConfigurationError') ||
            msg.contains('authId required') ||
            msg.contains('serverClientId')) {
          _showGoogleSetupDialog(
            initialNotice: 'Google Cloud configuration issue ($msg). Check that SHA-1 matches and OAuth Client ID is authorized for wtf.openstrap.openstrap_edge.',
          );
          return;
        }
        setState(() {
          _error = msg;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showGoogleSetupDialog({String? initialNotice}) async {
    final p = P.of(context);
    final currentClientId = await AccountService.instance.getGoogleServerClientId();
    final clientIdCtrl = TextEditingController(text: currentClientId);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: S.x4,
                right: S.x4,
                top: S.x5,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + S.x6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.keyRound, size: 22, color: C.blue),
                        const SizedBox(width: S.x2),
                        Text(
                          'Google Sign-In Setup',
                          style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: S.x2),
                    Text(
                      'Android Credential Manager requires an OAuth 2.0 Web Client ID to authenticate with Google.',
                      style: F.body.copyWith(color: p.ink2),
                    ),
                    if (initialNotice != null) ...[
                      const SizedBox(height: S.x3),
                      StatusCard('Notice', initialNotice, icon: LucideIcons.info),
                    ],
                    const SizedBox(height: S.x4),
                    Text('1. Package Name (for Android Client ID)',
                        style: F.cap.copyWith(color: p.ink3, fontWeight: FontWeight.bold)),
                    const SizedBox(height: S.x1),
                    _buildCopyTile(p, 'wtf.openstrap.openstrap_edge'),
                    const SizedBox(height: S.x3),
                    Text('2. Release SHA-1 Fingerprint',
                        style: F.cap.copyWith(color: p.ink3, fontWeight: FontWeight.bold)),
                    const SizedBox(height: S.x1),
                    _buildCopyTile(p, '24:5D:74:DE:5D:01:72:28:7A:1D:FC:D1:94:69:B6:AD:40:1D:DF:F6'),
                    const SizedBox(height: S.x4),
                    Text('3. Web Application Client ID',
                        style: F.cap.copyWith(color: p.ink3, fontWeight: FontWeight.bold)),
                    const SizedBox(height: S.x1),
                    OsTextField(
                      controller: clientIdCtrl,
                      hint: 'xxxxxx-xxxxxx.apps.googleusercontent.com',
                      label: 'OAuth Web Client ID',
                    ),
                    const SizedBox(height: S.x4),
                    BigButton(
                      'Save Client ID',
                      icon: LucideIcons.save,
                      color: C.blue,
                      onTap: () async {
                        final val = clientIdCtrl.text.trim();
                        await AccountService.instance.setGoogleServerClientId(val.isNotEmpty ? val : null);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Google Client ID updated!')),
                          );
                          if (val.isNotEmpty) {
                            _loginWithGoogle();
                          }
                        }
                      },
                    ),
                    const SizedBox(height: S.x3),
                    Center(
                      child: Text(
                        'Or sign in with email and password below — no Google Cloud setup required.',
                        textAlign: TextAlign.center,
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCopyTile(P p, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: R.rMd,
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: F.cap.copyWith(color: p.ink, fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.copy, size: 16, color: p.ink2),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
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
                              if (profile.photoUrl != null)
                                CircleAvatar(
                                  radius: 24,
                                  backgroundImage: NetworkImage(profile.photoUrl!),
                                  backgroundColor: p.wash(C.blue),
                                )
                              else
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: p.wash(C.blue),
                                  child: Icon(
                                    profile.authProvider == 'google'
                                        ? LucideIcons.userCheck
                                        : LucideIcons.user,
                                    color: C.blue,
                                    size: 24,
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
                                      profile.authProvider == 'google'
                                          ? 'Google Account'
                                          : 'Connected & Active',
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
                    // Sign in with Google Button
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _loading ? null : _loginWithGoogle,
                            borderRadius: R.rMd,
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: p.card,
                                borderRadius: R.rMd,
                                border: Border.all(color: p.line),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.string(_kGoogleLogoSvg, width: 20, height: 20),
                                  const SizedBox(width: S.x3),
                                  Text(
                                    _loading ? 'Connecting...' : 'Sign in with Google',
                                    style: F.body.copyWith(
                                      color: p.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: S.x2),
                        IconButton(
                          icon: Icon(LucideIcons.settings2, size: 20, color: p.ink2),
                          tooltip: 'Google Sign-In Settings',
                          onPressed: () => _showGoogleSetupDialog(),
                        ),
                      ],
                    ),
                    const SizedBox(height: S.x4),
                    Row(
                      children: [
                        Expanded(child: Divider(color: p.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: S.x3),
                          child: Text('or with email', style: F.cap.copyWith(color: p.ink3)),
                        ),
                        Expanded(child: Divider(color: p.line)),
                      ],
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
