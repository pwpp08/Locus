part of 'community.dart';

// The pieces every community screen uses: the avatar, a team's logo and
// banner, the busy ring, and the small helpers.

CommunityService get _svc => CommunityService.instance;

/// The colour a member picked, as their avatar's ring.
Color hueColor(int hue, {double lightness = .58}) =>
    HSLColor.fromAHSL(1, hue % 360 + 0.0, .62, lightness).toColor();

void _say(BuildContext c, String text) => ScaffoldMessenger.maybeOf(c)
    ?.showSnackBar(SnackBar(content: Text(text)));

Future<bool> _confirm(BuildContext c, String title, String body, String yes,
    {String no = 'No', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AppDialog(
      title: title,
      content: Text(body,
          textAlign: TextAlign.center,
          style: F.body.copyWith(color: P.of(d).ink2)),
      actions: [
        BigButton(no, soft: true, compact: true, fill: true,
            onTap: () => Navigator.of(d).pop(false)),
        BigButton(yes,
            compact: true,
            fill: true,
            tone: danger ? ButtonTone.danger : ButtonTone.standard,
            onTap: () => Navigator.of(d).pop(true)),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs [job] under the reference's dimmed page and big ring with [label]
/// (VERIFYING, SAVING, CREATING, LEAVING). Null when it failed; the failure
/// is said on the page.
Future<T?> _busy<T>(BuildContext c, String label, Future<T> Function() job) async {
  final nav = Navigator.of(c);
  var open = true;
  unawaited(showGeneralDialog<void>(
    context: c,
    barrierDismissible: false,
    barrierColor: C.char.withValues(alpha: .72),
    transitionDuration: Motion.base,
    pageBuilder: (_, _, _) => PopScope(canPop: false, child: _BusyRing(label)),
  ).whenComplete(() => open = false));
  try {
    return await job();
  } catch (e) {
    if (c.mounted) _say(c, communityError(e));
    return null;
  } finally {
    if (open) nav.pop();
  }
}

class _BusyRing extends StatelessWidget {
  final String label;
  const _BusyRing(this.label);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const d = S.x16 * 3;
    return Center(
      child: SizedBox.square(
        dimension: d,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.square(
            dimension: d,
            child: CircularProgressIndicator(
              strokeWidth: S.x3,
              color: C.dialStrain,
              backgroundColor: p.card,
              semanticsLabel: label,
            ),
          ),
          Text(label.toUpperCase(),
              style: F.head.copyWith(
                  color: p.ink, letterSpacing: 2.4, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// A picture from one of the community's buckets, by its path there.
class _RemoteImage extends StatelessWidget {
  final String bucket, path;
  final BoxFit fit;
  const _RemoteImage(this.bucket, this.path, {this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return FutureBuilder<String>(
      future: _svc.pictureUrl(path, bucket: bucket),
      builder: (c, s) => s.hasData
          ? Image.network(s.data!,
              fit: fit,
              errorBuilder: (_, _, _) => ColoredBox(color: p.card2),
              frameBuilder: (_, child, frame, sync) => sync || frame != null
                  ? child
                  : ColoredBox(color: p.card2))
          : ColoredBox(color: p.card2),
    );
  }
}

/// A member: their photo, or their initials on a disc, inside a ring. [ring]
/// colours the ring and [fill] draws only that much of it (the recovery
/// board's ring is the member's recovery); without them it is their colour.
class CommunityAvatar extends StatelessWidget {
  final String name;
  final int hue;
  final double size;
  final String? photo;
  final Color? ring;
  final double? fill;
  const CommunityAvatar(this.name, this.hue,
      {super.key, this.size = S.x10, this.photo, this.ring, this.fill});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final stroke = size >= S.x12 ? S.x1 : S.half;
    final face = ClipOval(
      child: photo != null
          ? _RemoteImage('avatars', photo!)
          : Container(
              color: hueColor(hue, lightness: .42),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(S.x1),
                  child: Text(
                    initialsOf(name),
                    style: (size >= S.x16 ? F.t2 : F.caps)
                        .copyWith(color: p.ink, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
    );
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          color: ring ?? hueColor(hue),
          track: p.track,
          fill: fill ?? 1,
          stroke: stroke,
        ),
        child: Padding(padding: EdgeInsets.all(stroke * 2), child: face),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color, track;
  final double fill, stroke;
  const _RingPainter(
      {required this.color,
      required this.track,
      required this.fill,
      required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke,
        size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (fill < 1) canvas.drawArc(r, 0, math.pi * 2, false, p..color = track);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * fill.clamp(0.0, 1.0), false,
        p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.color != color || o.fill != fill || o.track != track || o.stroke != stroke;
}

/// The logos a creator swipes through: a glyph on a coloured disc.
const _logos = <String, (IconData, int)>{
  'heart': (LucideIcons.heart, 340),
  'flame': (LucideIcons.flame, 18),
  'zap': (LucideIcons.zap, 46),
  'mountain': (LucideIcons.mountain, 200),
  'bike': (LucideIcons.bike, 188),
  'footprints': (LucideIcons.footprints, 160),
  'dumbbell': (LucideIcons.dumbbell, 0),
  'trophy': (LucideIcons.trophy, 40),
  'waves': (LucideIcons.waves, 205),
  'leaf': (LucideIcons.leaf, 130),
  'moon': (LucideIcons.moon, 255),
  'target': (LucideIcons.target, 355),
  'volleyball': (LucideIcons.volleyball, 280),
  'medal': (LucideIcons.medal, 30),
};

/// The banners a creator swipes through, bundled photos.
final _banners = [
  for (var i = 1; i <= 11; i++) 'banner_$i',
];

/// A team's logo: a bundled glyph disc, or the picture an admin uploaded.
class TeamLogo extends StatelessWidget {
  final String logo;
  final double size;
  const TeamLogo(this.logo, {super.key, this.size = S.x12});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    if (logo.startsWith('storage:')) {
      return SizedBox.square(
        dimension: size,
        child: ClipOval(child: _RemoteImage('teams', logo.substring(8))),
      );
    }
    final (icon, hue) = _logos[logo] ?? _logos['heart']!;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hueColor(hue, lightness: .62), hueColor(hue + 18, lightness: .46)],
        ),
      ),
      child: Icon(icon, size: size * .5, color: p.ink),
    );
  }
}

/// A team's banner photo, filling what it is given.
class TeamBanner extends StatelessWidget {
  final String banner;
  const TeamBanner(this.banner, {super.key});

  @override
  Widget build(BuildContext c) {
    if (banner.startsWith('storage:')) {
      return _RemoteImage('teams', banner.substring(8));
    }
    final key = _banners.contains(banner) ? banner : _banners.first;
    return _photo(key);
  }
}

/// A photo under a fade to the page: the banner behind a team's header, the
/// pictures behind the join and create pages.
class _Backdrop extends StatelessWidget {
  final Widget picture;
  final double height;

  /// How much of the photo shows through, 0-1.
  final double strength;
  const _Backdrop(this.picture, {required this.height, this.strength = .6});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        Opacity(opacity: strength, child: picture),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.bg.withValues(alpha: .35), p.bg.withValues(alpha: 0), p.bg],
              stops: const [0, .45, 1],
            ),
          ),
        ),
      ]),
    );
  }
}

/// The ringed round button of the reference's team headers (back, ⋯).
class _RingButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _RingButton(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: S.tap,
        child: Center(
          child: Container(
            width: S.x10,
            height: S.x10,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.ink, width: S.half),
            ),
            child: Icon(icon, size: I.md, color: p.ink),
          ),
        ),
      ),
    );
  }
}

/// Tracked caps, the reference's small section labels (ABOUT, 1 MEMBER).
Text _label(BuildContext c, String text, {Color? color}) => Text(
      text.toUpperCase(),
      style: F.caps.copyWith(
          color: color ?? P.of(c).ink, fontWeight: FontWeight.w800, letterSpacing: 1.4),
    );

/// A grey caption line under a label.
Text _grey(BuildContext c, String text) =>
    Text(text, style: F.body.copyWith(color: P.of(c).ink3));

/// One of the bundled community photos (assets/images/community), covering
/// its box; the card colour where it fails to load.
Widget _photo(String name) => Image.asset('assets/images/community/$name.jpg',
    fit: BoxFit.cover,
    errorBuilder: (c, _, _) => ColoredBox(color: P.of(c).card2));

/// The plain rounded card row of the community pages.
Widget _cardRow(BuildContext c,
        {required Widget child,
        VoidCallback? onTap,
        VoidCallback? onLongPress,
        String? label,
        EdgeInsets? padding}) =>
    Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: label,
      child: Container(
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: BoxDecoration(color: P.of(c).card, borderRadius: R.rXl),
        child: child,
      ),
    );

/// The app's username and birth year, for a new community profile.
({String? name, String? username, int? birthYear}) _setupIdentity(BuildContext c) {
  try {
    final u = c.read<AppState>().user;
    final first = (u?['first_name'] as String?)?.trim() ?? '';
    final last = (u?['last_name'] as String?)?.trim() ?? '';
    final full = '$first $last'.trim();
    final age = (u?['age'] as num?)?.toInt();
    return (
      name: full.isEmpty ? (u?['name'] as String?) : full,
      username: u?['username'] as String?,
      birthYear: age == null ? null : DateTime.now().year - age,
    );
  } catch (_) {
    return (name: null, username: null, birthYear: null);
  }
}

/// Signs the person in if they are not (the anonymous account, named from
/// setup). False when that failed; the reason is said.
Future<bool> _ensureSignedIn(BuildContext c) async {
  await _svc.ensureReady();
  if (_svc.signedIn) return true;
  if (!c.mounted) return false;
  final id = _setupIdentity(c);
  final ok = await _busy(c, 'Joining', () async {
    await _svc.join(name: id.name, username: id.username, birthYear: id.birthYear);
    return true;
  });
  return ok == true;
}

/// Hands the repository to the service, so it can put the numbers up.
void _attachRepo(BuildContext c) {
  _svc.repo ??= repoOf(c);
}
