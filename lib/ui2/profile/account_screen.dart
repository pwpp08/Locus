// The cloud account: sign in to back the data up, and once signed in, when it
// last went up, where to, and the switch that keeps it going.

import 'package:flutter/material.dart';

import '../../cloud/account_service.dart';
import '../screens/home_screen.dart' show clockOfTs;
import '../screens/metric_detail.dart' show detailScaffold;
import '../ui2.dart';
import 'profile.dart' show SetRow, settingsGroup;

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _done;

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

  Future<void> _run(Future<String> Function() job) async {
    setState(() {
      _loading = true;
      _error = null;
      _done = null;
    });
    try {
      final said = await job();
      if (mounted) setState(() => _done = said);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'
            .replaceFirst('Exception: ', '')
            .replaceFirst('ArgumentError: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() => _run(() async {
        await AccountService.instance.logIn(
          email: _email.text,
          passwordOrToken: _password.text,
          customServerUrl: _server.text.isNotEmpty ? _server.text : null,
        );
        return 'Signed in, and your data is backed up.';
      });

  Future<void> _sync() => _run(() async {
        final ok = await AccountService.instance.syncNow();
        return ok
            ? 'Backed up.'
            : 'The backup did not finish. Check the connection and try again.';
      });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final account = AccountService.instance;
    final profile = account.current;
    final signedIn = account.isLoggedIn && profile != null;
    final busy = _loading || account.isSyncing;
    return detailScaffold(
      c,
      'Cloud account',
      [
        if (_error != null) ...[
          const SizedBox(height: S.x2),
          StatusCard('That did not work', _error!,
              icon: LucideIcons.circleAlert),
        ],
        if (_done != null) ...[
          const SizedBox(height: S.x3),
          Row(children: [
            Icon(LucideIcons.badgeCheck, size: I.md, color: p.ink2),
            const SizedBox(width: S.x2),
            Expanded(
                child: Text(_done!, style: F.body.copyWith(color: p.ink2))),
          ]),
        ],
        if (signedIn) ...[
          settingsGroup(c, 'Signed in', [
            SetRow(LucideIcons.userRound, C.dialStrain,
                profile.displayName?.isNotEmpty == true
                    ? profile.displayName!
                    : profile.email,
                sub: profile.displayName?.isNotEmpty == true
                    ? profile.email
                    : '',
                keepCase: true,
                chevron: false),
            SetRow(LucideIcons.cloud, C.dialStrain, 'Last backup',
                value: profile.lastSyncTime == null
                    ? 'Never'
                    : clockOfTs(
                        profile.lastSyncTime!.millisecondsSinceEpoch ~/ 1000),
                chevron: false),
            SetRow(LucideIcons.server, C.dialStrain, 'Server',
                value: profile.serverUrl ?? 'Locus Cloud', chevron: false),
            SetRow(LucideIcons.refreshCw, C.dialStrain, 'Back up automatically',
                sub: 'Uploads a backup from time to time while signed in',
                switchValue: profile.autoSync,
                onTap: () => account.setAutoSync(!profile.autoSync)),
          ]),
          const SizedBox(height: S.x8),
          BigButton(
            busy ? 'Backing up…' : 'Back up now',
            icon: LucideIcons.cloudUpload,
            busy: busy,
            onTap: busy ? null : _sync,
          ),
          const SizedBox(height: S.x4),
          Center(
            child: TextAction('Sign out', () async {
              await account.logOut();
              if (mounted) setState(() => _done = 'Signed out.');
            }),
          ),
        ] else ...[
          const SizedBox(height: S.x2),
          Text(
            'Sign in to back up your scores, sleep and history. Everything '
            'still works without an account.',
            style: F.body.copyWith(color: p.ink2, height: 1.4),
          ),
          const SizedBox(height: S.x6),
          AppField(
            label: 'Email',
            controller: _email,
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: S.x4),
          AppField(
            label: 'Password or access key',
            controller: _password,
            obscure: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: S.x4),
          AppField(
            label: 'Server (optional)',
            controller: _server,
            hint: 'https://cloud.openstrap.org',
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: S.x8),
          BigButton(
            _loading ? 'Signing in…' : 'Sign in',
            icon: LucideIcons.logIn,
            busy: _loading,
            onTap: _loading ? null : _login,
          ),
        ],
      ],
    );
  }
}
