// Getting the Helio Strap's pairing key onto this phone, before the strap is
// searched for. Two ways in: sign in to the owner's own Zepp account and let
// Locus read the key Zepp holds for the strap, or type the key in.
//
// The sign-in is Zepp's own page in a WebView. Locus never sees the password;
// it only reads the session cookie the page sets, asks Zepp for the account's
// device list (the same request the Zepp app makes), takes the strap's key and
// forgets the cookies. Google and Apple sign-in do not work in a WebView, so
// the screen says so before the page opens.
//
// [HelioKeyCard] sits on the pairing screen; [ZeppSignInScreen] is the route
// it opens.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../ble/helio/channel.dart' show helioParseAuthKey;
import '../../ble/helio/zepp_cloud.dart';
import '../../ble/helio/zepp_cookies.dart';
import '../../ble/helio_link.dart';
import '../../l10n/display_text.dart';
import '../ui2.dart';
import 'profile.dart' show goto;

/// The card on the strap's pairing screen: whether a key is waiting, and the
/// two ways to get one.
class HelioKeyCard extends StatefulWidget {
  const HelioKeyCard({super.key});

  @override
  State<HelioKeyCard> createState() => _HelioKeyCardState();
}

class _HelioKeyCardState extends State<HelioKeyCard> {
  HelioPendingKey? _pending;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final k = await readHelioPendingKey();
    if (!mounted) return;
    setState(() {
      _pending = k;
      _loaded = true;
    });
  }

  Future<void> _signIn() async {
    await goto(context, const ZeppSignInScreen());
    await _load();
  }

  void _type() {
    final ctl = TextEditingController();
    AppSheet.show<void>(context,
        title: 'Enter the strap’s key',
        child: Builder(builder: (sc) {
          final p = P.of(sc);
          String? error;
          return StatefulBuilder(builder: (sc, setSheet) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                uiText(sc, '32 characters, 0 to 9 and a to f. Spaces and colons are fine.'),
                style: F.cap.copyWith(color: p.ink3, height: 1.5),
              ),
              const SizedBox(height: S.x3),
              AppField(
                label: 'Key',
                controller: ctl,
                autocorrect: false,
                enableSuggestions: false,
                errorText: error,
              ),
              const SizedBox(height: S.x4),
              BigButton('SAVE', compact: true, fill: true, onTap: () async {
                final key = helioParseAuthKey(ctl.text);
                if (key == null) {
                  setSheet(() => error = 'That is not 32 hex characters.');
                  return;
                }
                await saveHelioPendingKey(key);
                if (sc.mounted) Navigator.of(sc).pop();
                await _load();
              }),
            ]);
          });
        }));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final has = _pending != null;
    final mac = _pending?.mac;
    return Section(
      'Step 1: the strap’s key',
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            uiText(
                c,
                'The strap only talks to a phone that holds the key Zepp made '
                'when you first linked it. Locus can fetch that key from your Zepp '
                'account once. It does not see your password.'),
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
          const SizedBox(height: S.x3),
          Text(
            !_loaded
                ? ''
                : has
                    ? uiText(c, mac == null ? 'A key is ready.' : 'A key is ready for the strap $mac.')
                    : uiText(c, 'No key yet.'),
            style: F.cap.copyWith(color: has ? p.ink : p.ink3),
          ),
          const SizedBox(height: S.x3),
          Row(children: [
            Expanded(
              child: BigButton('SIGN IN TO ZEPP',
                  compact: true, fill: true, soft: has, onTap: _signIn),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: BigButton('ENTER IT', compact: true, fill: true, soft: true, onTap: _type),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// What the sign-in screen is doing.
enum _Phase { signIn, looking, done, problem }

/// Zepp's own sign-in page, then the strap's key from the account.
class ZeppSignInScreen extends StatefulWidget {
  const ZeppSignInScreen({super.key});

  @override
  State<ZeppSignInScreen> createState() => _ZeppSignInScreenState();
}

class _ZeppSignInScreenState extends State<ZeppSignInScreen> {
  late final WebViewController _web;
  _Phase _phase = _Phase.signIn;
  String? _message;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _look(),
        onUrlChange: (_) => _look(),
      ))
      ..loadRequest(Uri.parse(kZeppSignInUrl));
  }

  @override
  void dispose() {
    // The sign-in is for one use: its cookies go with the screen.
    clearZeppCookies();
    super.dispose();
  }

  /// Checks whether the page has set a session yet; called on every page event.
  Future<void> _look() async {
    if (_checking || _phase != _Phase.signIn) return;
    _checking = true;
    try {
      final session = zeppSessionFromCookies(await readZeppCookieHeader());
      if (session == null || !mounted) return;
      setState(() => _phase = _Phase.looking);
      await _fetch(session);
    } finally {
      _checking = false;
    }
  }

  Future<void> _fetch(ZeppSession session) async {
    final cloud = ZeppCloud();
    try {
      final lang = Localizations.localeOf(context);
      final devices = await cloud.listDevices(session,
          lang: lang.languageCode, country: lang.countryCode ?? 'US');
      final strap = pickHelioStrap(devices);
      if (strap == null) {
        return _stop(_Phase.problem,
            'That Zepp account has no Helio Strap on it. Link the strap in the Zepp app first, then come back.');
      }
      if (strap.key == null) {
        return _stop(_Phase.problem,
            'Zepp has the strap but gave no key for it. Unlink and link the strap again in the Zepp app, then come back.');
      }
      await saveHelioPendingKey(strap.key!, mac: strap.mac);
      await clearZeppCookies();
      _stop(_Phase.done, 'Found your strap ${strap.mac}. The key is saved on this phone.');
    } on ZeppCloudException catch (e) {
      _stop(
          _Phase.problem,
          switch (e.kind) {
            ZeppFailure.rejected => 'Zepp did not accept that sign-in. Try again with your email and password.',
            ZeppFailure.unreachable => 'Could not reach Zepp. Check the connection and try again.',
            ZeppFailure.unreadable => 'Zepp answered in a way this app could not read.',
          });
    } finally {
      cloud.close();
    }
  }

  void _stop(_Phase phase, String message) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Zepp sign-in', sub: 'Helio Strap'),
          ),
          if (_phase == _Phase.signIn) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x3),
              child: Text(
                uiText(
                    c,
                    'Sign in with your email and password. Google and Apple sign-in do '
                    'not work here. If your Zepp account uses one of them, set a '
                    'password on it in the Zepp app first. Locus only reads the '
                    'strap’s key and forgets the sign-in afterwards.'),
                style: F.cap.copyWith(color: p.ink3, height: 1.5),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x4),
                child: ClipRRect(
                  borderRadius: R.rMd,
                  child: WebViewWidget(controller: _web),
                ),
              ),
            ),
          ] else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x10),
                children: [
                  if (_phase == _Phase.looking)
                    const StatusCard('Looking for your strap', 'Asking Zepp for the devices on your account.',
                        icon: LucideIcons.search)
                  else if (_phase == _Phase.done)
                    StatusCard('Key saved', _message ?? '', icon: LucideIcons.check)
                  else
                    StatusCard('That did not work', _message ?? '', icon: LucideIcons.circleAlert),
                  const SizedBox(height: S.x4),
                  if (_phase != _Phase.looking)
                    BigButton(_phase == _Phase.done ? 'DONE' : 'CLOSE', compact: true, fill: true,
                        onTap: () => Navigator.of(c).pop()),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
