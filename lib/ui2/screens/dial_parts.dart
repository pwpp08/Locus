// The parts the Sleep and Recovery dial screens share: the page, the ring, the
// panel with its caret, the hatched bars and the seven-day charts. Every size
// here was measured off the reference recordings at 1.5 px to the dp (DC).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'home_screen.dart' show monthShortName, pointsOf, weekdayShortName;
import 'trend_view.dart' show TrendViewScreen, shiftDay;

/// The screen's side margin, and the inset of a card's own content.
const kDialMargin = S.x4 + S.half;
const kDialPad = S.x4 + S.half;

/// 'H:MM' for a duration, or '--' when there is none.
String clockDur(num? minutes) {
  if (minutes == null) return '--';
  final m = minutes.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// 'Fri, May 16', as the screens name a day.
String dialDayName(String? day, AppLocalizations? l) {
  final d = day == null ? null : DateTime.tryParse(day);
  if (d == null) return '';
  return '${weekdayShortName(d.weekday, l)}, ${monthShortName(d.month, l)} ${d.day}';
}

/// A stored series as value per local day.
Future<Map<String, double>> dialSeries(LocalRepository repo, String key) async {
  final out = <String, double>{};
  for (final p in pointsOf(await repo.getChart(key))) {
    out[dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000))] = p.v;
  }
  return out;
}

/// A night's bed and wake in minutes after noon, keyed by the day it ended.
/// [bed] of 420 is 19:00; [wake] runs on past 720 (midnight) to the morning.
typedef BedWake = ({double bed, double wake});

BedWake? bedWakeOf(num on, num off) {
  if (off <= on) return null;
  final a = DateTime.fromMillisecondsSinceEpoch(on.toInt() * 1000);
  final bed = (((a.hour * 60 + a.minute) - 720) % 1440).toDouble();
  return (bed: bed, wake: bed + (off - on) / 60);
}

/// [nights] nights of bed and wake, up to and including [day].
Future<Map<String, BedWake>> bedAndWake(LocalRepository repo,
    {required String day, required int nights}) async {
  final out = <String, BedWake>{};
  final after = shiftDay(day, 1);
  for (final w in await repo.sleepWindows(days: nights, before: after)) {
    final on = w['onset_ts'], off = w['wake_ts'];
    if (on is! num || off is! num) continue;
    final s = bedWakeOf(on, off);
    if (s == null) continue;
    final at = dayLabelOf(DateTime.fromMillisecondsSinceEpoch(off.toInt() * 1000));
    if (at.compareTo(day) <= 0) out[at] = s;
  }
  return out;
}

/// The page: the fixed ground, the bar, and a list clipped under the bar.
class DialScaffold extends StatefulWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  /// The bar's height under the status bar, and its line's distance from the
  /// top of it. Behavior Insights sits a little lower than the others.
  final double barHeight, titleAt;

  /// Painted behind the page's content, scrolling with nothing: the hero glow
  /// of a behaviour.
  final Widget? backdrop;

  const DialScaffold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.barHeight = 81,
    this.titleAt = 32,
    this.backdrop,
  });

  @override
  State<DialScaffold> createState() => _DialScaffoldState();
}

class _DialScaffoldState extends State<DialScaffold> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return AlwaysChar(
      child: Scaffold(
        backgroundColor: DC.bgFoot,
        body: Stack(children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .47, 1],
                  colors: [DC.bgTop, DC.bgMid, DC.bgFoot],
                ),
              ),
            ),
          ),
          ?widget.backdrop,
          SafeArea(
            bottom: false,
            child: Column(children: [
              SizedBox(
                height: widget.barHeight,
                child: Stack(children: [
                  Positioned(
                    left: S.x6 + S.hair,
                    top: widget.titleAt - S.x6,
                    child: Pressable(
                      onTap: () => Navigator.of(c).maybePop(),
                      semanticLabel: AppLocalizations.of(c)?.supplementNavBack ?? 'Back',
                      child: const SizedBox(
                        width: S.x12,
                        height: S.x12,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CustomPaint(
                              size: Size(S.x3 + S.hair + S.hair, S.x6),
                              painter: _BackPaint()),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: S.x16,
                    right: S.x16,
                    top: widget.titleAt - S.x2,
                    child: Center(
                      child: Text(widget.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.dNav.copyWith(color: DC.ink)),
                    ),
                  ),
                  if (widget.trailing != null)
                    Positioned(
                      right: S.x4 + S.half + S.hair,
                      top: widget.titleAt - S.x4 - S.half,
                      child: widget.trailing!,
                    ),
                ]),
              ),
              Expanded(
                child: RawScrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  thickness: S.half + S.hair,
                  radius: const Radius.circular(S.half),
                  thumbColor: DC.edge,
                  crossAxisMargin: S.hair,
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                        kDialMargin, 0, kDialMargin, S.x16),
                    children: widget.children,
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The bar's back mark, a size heavier than the icon set's.
class _BackPaint extends CustomPainter {
  const _BackPaint();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..moveTo(size.width - S.hair, S.hair)
          ..lineTo(S.hair, size.height / 2)
          ..lineTo(size.width - S.hair, size.height - S.hair),
        Paint()
          ..color = DC.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = S.half
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_BackPaint old) => false;
}

/// The hero ring and what sits inside it. 75 % of the page across, 6 % stroke.
class DialRing extends StatelessWidget {
  final double? fraction;
  final Color color;
  final Widget child;
  const DialRing(
      {super.key,
      required this.fraction,
      required this.color,
      required this.child});

  @override
  Widget build(BuildContext c) {
    return LayoutBuilder(builder: (c, box) {
      final side = MediaQuery.sizeOf(c).width * .75;
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: Size.square(side),
              painter: Ring((fraction ?? 0).clamp(0.0, 1.0), color, DC.track,
                  stroke: side * .06,
                  solid: true,
                  flatStart: true,
                  softStart: true,
                  t: animate(c, 1)),
            ),
            FittedBox(fit: BoxFit.scaleDown, child: child),
          ]),
        ),
      );
    });
  }
}

/// The figure inside a ring, its % a smaller size on the same baseline.
Widget dialFigure(double? value, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(value == null ? '--' : '${value.round()}',
          style: F.nDial.copyWith(color: color)),
      if (value != null) ...[
        const SizedBox(width: S.half),
        Text('%', style: F.nDialPct.copyWith(color: color)),
      ],
    ],
  );
}

/// The panel under a ring: a faint glow from the top, an edge that fades
/// downward, and a caret pointing up at the ring.
class CaretPanel extends StatelessWidget {
  final Widget child;
  const CaretPanel({super.key, required this.child});

  @override
  Widget build(BuildContext c) {
    return CustomPaint(
      painter: _CaretPanelPaint(),
      child: Padding(
        padding: const EdgeInsets.only(top: S.x4 + S.half),
        child: child,
      ),
    );
  }
}

class _CaretPanelPaint extends CustomPainter {
  static const _caretW = S.x3, _caretH = S.x1 + S.hair + S.hair;

  @override
  void paint(Canvas canvas, Size size) {
    const r = R.xxl;
    final mid = size.width / 2;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, r + _caretH)
      ..arcToPoint(Offset(r, _caretH), radius: const Radius.circular(r))
      ..lineTo(mid - _caretW / 2, _caretH)
      ..lineTo(mid, 0)
      ..lineTo(mid + _caretW / 2, _caretH)
      ..lineTo(size.width - r, _caretH)
      ..arcToPoint(Offset(size.width, r + _caretH),
          radius: const Radius.circular(r))
      ..lineTo(size.width, size.height);
    final box = Offset.zero & size;
    canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.topCenter,
            radius: .6,
            colors: [
              DC.pressGlow,
              DC.pressGlow.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.width * .9)));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [DC.edge, DC.edge.withValues(alpha: 0)],
            stops: const [.05, .55],
          ).createShader(box));
  }

  @override
  bool shouldRepaint(_CaretPanelPaint old) => false;
}

/// Three ticks, one lit: poor, sufficient, optimal.
class TierBar extends StatelessWidget {
  /// 0 poor, 1 sufficient, 2 optimal, null nothing to say.
  final int? tier;
  const TierBar(this.tier, {super.key});

  static Color colorOf(int t) => [C.poor, DC.tierMid, C.optimal][t];

  @override
  Widget build(BuildContext c) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: S.half),
        Container(
          width: S.x6 - S.hair,
          height: S.x1,
          decoration: BoxDecoration(
            color: i == tier ? colorOf(i) : DC.tierOff,
            borderRadius: const BorderRadius.all(Radius.circular(S.hair)),
          ),
        ),
      ],
    ]);
  }
}

/// A value, the triangle that says which side of the usual it is on.
class ValueDelta extends StatelessWidget {
  final String value;
  final TextStyle style;
  final double? v, usual;

  /// Whether more is better, or null when neither is (green is only for a
  /// better reading).
  final bool higherBetter;
  const ValueDelta(this.value,
      {super.key,
      required this.style,
      required this.v,
      required this.usual,
      this.higherBetter = true});

  @override
  Widget build(BuildContext c) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: style.copyWith(color: DC.ink)),
        ?deltaMark(v, usual, higherBetter),
      ]),
    );
  }
}

/// The triangle beside a value, or nothing with no comparison.
Widget? deltaMark(double? v, double? usual, bool higherBetter,
    {double size = S.x2 + S.hair}) {
  if (v == null || usual == null) return null;
  final up = v >= usual;
  final good = up == higherBetter;
  return Padding(
    padding: const EdgeInsets.only(left: S.x1 + S.hair),
    child: DeltaTriangle(
        up: up, color: good ? C.optimal : C.strainDown, size: size),
  );
}

/// The ⓘ on a card's title line: what the figure is, in a sheet.
class DialInfo extends StatelessWidget {
  final String title, body;
  const DialInfo(this.title, this.body, {super.key});

  @override
  Widget build(BuildContext c) {
    return Pressable(
      onTap: () => AppSheet.show<void>(c,
          title: title,
          child: Text(body, style: F.dBody.copyWith(color: P.of(c).ink2))),
      semanticLabel: 'About $title',
      child: const Icon(LucideIcons.info, size: I.md, color: DC.ink2),
    );
  }
}

/// A card's top: the capitals on the left, ⓘ or chevron on the right.
Widget dialCardTitle(String title, {Widget? trailing}) {
  return Row(children: [
    Expanded(
      child: Text(title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: F.dLabel.copyWith(color: DC.ink)),
    ),
    ?trailing,
  ]);
}

/// A plain card ground: a veil of white over the page, 17 pt corners.
BoxDecoration dialCard([Color color = DC.card]) =>
    BoxDecoration(color: color, borderRadius: R.rXxl);

/// A section title between cards, 'Last Night's Sleep' and 'Weekly Trends'.
Widget dialHeading(String text) => Padding(
      padding: const EdgeInsets.only(left: S.x1 + S.hair),
      child: Text(text, style: F.dTitle.copyWith(color: DC.ink)),
    );

// ── Hatched bars ────────────────────────────────────────────────────────────

/// The slanted stripes every bar runs on.
void paintHatch(Canvas canvas, Rect r, {double radius = S.x1}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
  canvas.save();
  canvas.clipRRect(rr);
  canvas.drawRect(r, Paint()..color = DC.hatchBase);
  final line = Paint()
    ..color = DC.hatchLine
    ..strokeWidth = S.half;
  const step = S.x1 + S.hair;
  for (var x = r.left - r.height; x < r.right + r.height; x += step) {
    canvas.drawLine(
        Offset(x, r.bottom), Offset(x + r.height, r.top), line);
  }
  canvas.restore();
}

/// A bar on the stripes: [fill] of it solid, in one colour.
class HatchBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final double height;
  const HatchBar(this.fraction, this.color,
      {super.key, this.height = S.x4 + S.half});

  @override
  Widget build(BuildContext c) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _HatchBarPaint(fraction, color),
    );
  }
}

class _HatchBarPaint extends CustomPainter {
  final double fraction;
  final Color color;
  _HatchBarPaint(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    paintHatch(canvas, box);
    final w = size.width * fraction.clamp(0.0, 1.0);
    if (w <= 0) return;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, math.max(w, S.x1), size.height),
            const Radius.circular(S.x1)),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HatchBarPaint old) =>
      old.fraction != fraction || old.color != color;
}

// ── Seven days ──────────────────────────────────────────────────────────────

/// One day's column in a [WeekChart].
class WeekColumn {
  /// From the axis foot to [hi] in axis units, or from [lo] to [hi] for a
  /// floating bar. Null hi: nothing that day.
  final double? lo, hi;
  final Color color;

  /// Bottom-up segments in place of one colour, in axis units, summing to [hi].
  final List<(double, Color)>? stack;

  /// The figures above the bar and, for a floating one, below it.
  final String top, bottom;
  final Color? topColor;

  /// A stack's figure rides on the bar instead of over the plot.
  final bool floatLabel;
  const WeekColumn({
    this.lo,
    this.hi,
    this.color = C.dialSleep,
    this.stack,
    this.top = '',
    this.bottom = '',
    this.topColor,
    this.floatLabel = false,
  });
}

/// One line of a line chart: a value a day, a label for each.
class WeekLine {
  final List<double?> values;
  final List<String> labels;
  final Color color;

  /// Figures under the points instead of over them.
  final bool below;

  /// A soft fill down to the foot of the plot.
  final bool area;
  const WeekLine({
    required this.values,
    required this.labels,
    required this.color,
    this.below = false,
    this.area = false,
  });
}

/// The chart in a Weekly Trends card: seven days, a grid of five lines, the
/// newest day under a lighter column, its name in white.
class WeekChart extends StatelessWidget {
  /// Seven 'YYYY-MM-DD', oldest first.
  final List<String> days;
  final List<WeekColumn>? columns;
  final List<WeekLine>? lines;
  final double lo, hi;

  /// A floating chart's axis runs downward: [lo] is at the top.
  final bool inverted;
  const WeekChart({
    super.key,
    required this.days,
    this.columns,
    this.lines,
    required this.lo,
    required this.hi,
    this.inverted = false,
  });

  /// 53 pt between grid lines, then the day's two lines of name, the column's
  /// tail under them.
  static const plot = 212.0, foot = 44.0, head = 14.0;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final d = [for (final s in days) DateTime.parse(s)];
    return SizedBox(
      height: head + plot + foot,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WeekPaint(
          names: [for (final x in d) weekdayShortName(x.weekday, l)],
          dates: [for (final x in d) '${x.day}'],
          columns: columns,
          lines: lines,
          lo: lo,
          hi: hi,
          inverted: inverted,
          scaler: MediaQuery.textScalerOf(c),
        ),
      ),
    );
  }
}

class _WeekPaint extends CustomPainter {
  final List<String> names, dates;
  final List<WeekColumn>? columns;
  final List<WeekLine>? lines;
  final double lo, hi;
  final bool inverted;
  final TextScaler scaler;
  _WeekPaint({
    required this.names,
    required this.dates,
    required this.columns,
    required this.lines,
    required this.lo,
    required this.hi,
    required this.inverted,
    required this.scaler,
  });

  void _text(Canvas canvas, String s, TextStyle st, Offset centre) {
    if (s.isEmpty) return;
    final tp = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler)
      ..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const inset = kDialPad, centreInset = S.x8;
    const top = WeekChart.head;
    const plot = WeekChart.plot;
    final bottom = top + plot;
    final n = names.length;
    final x0 = centreInset;
    final dx = (size.width - 2 * centreInset) / (n - 1);
    double xOf(int i) => x0 + dx * i;
    double yOf(double v) {
      final f = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
      return inverted ? top + plot * f : bottom - plot * f;
    }

    // The newest day's column, behind everything else.
    const colW = S.x8 - S.hair - S.hair;
    final col = RRect.fromRectAndRadius(
        Rect.fromLTRB(xOf(n - 1) - colW / 2, top - S.x2 - S.half,
            xOf(n - 1) + colW / 2, size.height),
        const Radius.circular(R.sm));
    canvas.drawRRect(
        col,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [DC.column, DC.columnFoot],
          ).createShader(col.outerRect));

    // Five grid lines.
    final grid = Paint()
      ..color = DC.grid
      ..strokeWidth = S.hair;
    for (var i = 0; i <= 4; i++) {
      final y = top + plot * i / 4;
      canvas.drawLine(
          Offset(inset, y), Offset(size.width - inset, y), grid);
    }

    final cols = columns;
    if (cols != null) {
      const barW = S.x4 - S.hair;
      for (var i = 0; i < cols.length && i < n; i++) {
        final c = cols[i];
        final h = c.hi;
        if (h == null) continue;
        final x = xOf(i);
        final yTop = yOf(h);
        final yLow = c.lo == null ? bottom : yOf(c.lo!);
        final labelTop = c.topColor ?? c.color;
        final st = (c.top.contains(':') ? F.nWeek : F.nSmall)
            .copyWith(color: labelTop);
        if (c.stack != null) {
          // As Trend View stacks them: each segment rounded, a sliver of the
          // card between one and the next, the foot square on the axis.
          final parts = <(Rect, Color)>[];
          var v = 0.0;
          for (final (amount, color) in c.stack!) {
            final y0 = yOf(v), y1 = yOf(v + amount);
            if ((y0 - y1).abs() >= .5) {
              parts.add((Rect.fromLTRB(x - barW / 2, math.min(y0, y1),
                  x + barW / 2, math.max(y0, y1)), color));
            }
            v += amount;
          }
          const gap = 1.5;
          for (var k = 0; k < parts.length; k++) {
            final foot = k == 0, crown = k == parts.length - 1;
            final r = parts[k].$1;
            final r0 = Rect.fromLTRB(r.left, r.top + (crown ? 0 : gap / 2),
                r.right, r.bottom - (foot ? 0 : gap / 2));
            if (r0.height < 1) continue;
            final rad = Radius.circular(
                math.min(math.min(3.0, barW / 3), r0.height / 2));
            canvas.drawRRect(
                RRect.fromRectAndCorners(r0,
                    topLeft: rad,
                    topRight: rad,
                    bottomLeft: foot ? Radius.zero : rad,
                    bottomRight: foot ? Radius.zero : rad),
                Paint()..color = parts[k].$2);
          }
        } else {
          canvas.drawRRect(
              RRect.fromRectAndCorners(
                Rect.fromLTRB(x - barW / 2, yTop, x + barW / 2, yLow),
                topLeft: const Radius.circular(S.hair + S.hair),
                topRight: const Radius.circular(S.hair + S.hair),
                bottomLeft: c.lo == null
                    ? Radius.zero
                    : const Radius.circular(S.hair + S.hair),
                bottomRight: c.lo == null
                    ? Radius.zero
                    : const Radius.circular(S.hair + S.hair),
              ),
              Paint()..color = c.color);
        }
        _text(canvas, c.top, st,
            Offset(x, c.stack != null && !c.floatLabel ? top - S.x3 - S.half : yTop - S.x4 + S.hair));
        _text(canvas, c.bottom, st, Offset(x, yLow + S.x4 - S.hair));
      }
    }

    for (final line in lines ?? const <WeekLine>[]) {
      final path = Path();
      final pts = <Offset?>[];
      var started = false;
      for (var i = 0; i < line.values.length && i < n; i++) {
        final v = line.values[i];
        if (v == null) {
          pts.add(null);
          continue;
        }
        final o = Offset(xOf(i), yOf(v));
        pts.add(o);
        started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
        started = true;
      }
      final known = [for (final o in pts) ?o];
      if (known.isEmpty) continue;
      if (line.area) {
        final fill = Path.from(path)
          ..lineTo(known.last.dx, bottom)
          ..lineTo(known.first.dx, bottom)
          ..close();
        canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  line.color.withValues(alpha: .22),
                  line.color.withValues(alpha: .02),
                ],
              ).createShader(Rect.fromLTRB(0, top, size.width, bottom)));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = line.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = S.half
            ..strokeJoin = StrokeJoin.round);
      final ring = Paint()
        ..color = line.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = S.half;
      final hole = Paint()..color = DC.weekHole;
      final label = F.nWeek.copyWith(color: line.color);
      final small = F.nSmall.copyWith(color: line.color);
      for (var i = 0; i < pts.length; i++) {
        final o = pts[i];
        if (o == null) continue;
        canvas.drawCircle(o, S.x1, hole);
        canvas.drawCircle(o, S.x1, ring);
        final text = i < line.labels.length ? line.labels[i] : '';
        _text(canvas, text, text.contains(':') ? label : small,
            o + Offset(0, line.below ? S.x5 : -S.x5));
      }
    }

    // The two lines of day name.
    for (var i = 0; i < n; i++) {
      final me = i == n - 1;
      _text(
          canvas,
          names[i],
          F.dTiny.copyWith(
              color: me ? DC.ink : DC.ink3,
              fontWeight: me ? FontWeight.w600 : FontWeight.w500),
          Offset(xOf(i), bottom + S.x4));
      _text(
          canvas,
          dates[i],
          F.dTiny.copyWith(
              color: me ? DC.ink : DC.ink3,
              fontWeight: me ? FontWeight.w700 : FontWeight.w500),
          Offset(xOf(i), bottom + S.x8 - S.hair));
    }
  }

  @override
  bool shouldRepaint(_WeekPaint old) => true;
}

/// A Weekly Trends card: its title and chevron, an optional key, the chart.
/// The chevron opens Trend View on [metricId].
class WeekCard extends StatelessWidget {
  final String title, metricId;
  final Widget? legend;
  final Widget chart;

  /// Space between the title line and the chart's top grid line.
  final double gap;

  /// Opens something other than Trend View on [metricId].
  final VoidCallback? onOpen;
  const WeekCard({
    super.key,
    required this.title,
    required this.metricId,
    required this.chart,
    this.legend,
    this.gap = S.x3 + S.hair,
    this.onOpen,
  });

  @override
  Widget build(BuildContext c) {
    return Pressable(
      onTap: onOpen ??
          () => Navigator.of(c).push(MaterialPageRoute(
              builder: (_) => TrendViewScreen(initial: metricId))),
      semanticLabel: '$title: open trend view',
      child: Container(
        margin: const EdgeInsets.only(bottom: S.x4 + S.half + S.hair),
        padding: const EdgeInsets.only(bottom: S.x6 + S.x1),
        decoration: dialCard(DC.weekCard),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                kDialPad, S.x6 - S.hair, S.x4, 0),
            child: dialCardTitle(title,
                trailing: const Icon(LucideIcons.chevronRight,
                    size: I.md, color: DC.ink2)),
          ),
          if (legend != null) ...[
            const SizedBox(height: S.x6 + S.half),
            Padding(
              padding: const EdgeInsets.only(right: S.x8 + S.x1 + S.half),
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: legend),
              ),
            ),
          ],
          SizedBox(height: gap),
          chart,
        ]),
      ),
    );
  }
}

/// The key above a card's chart. [dots] draws hollow dots, otherwise squares.
Widget weekLegend(List<(String, Color)> items, {bool dots = false}) {
  return Row(mainAxisSize: MainAxisSize.min, children: [
    for (var i = 0; i < items.length; i++) ...[
      if (i > 0) const SizedBox(width: S.x4 + S.hair),
      Container(
        width: dots ? S.x2 + S.hair : S.x3 + S.hair,
        height: dots ? S.x2 + S.hair : S.x3 + S.hair,
        decoration: dots
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: items[i].$2, width: S.half))
            : BoxDecoration(color: items[i].$2),
      ),
      const SizedBox(width: S.x2 + S.hair),
      Text(items[i].$1.toUpperCase(), style: F.dLabel.copyWith(color: DC.ink)),
    ],
  ]);
}

/// Lines' axis, as the reference scales it: a fifth under the lowest reading
/// and a fifth over the highest.
(double, double) weekLineAxis(Iterable<double?> values) {
  final known = [for (final v in values) ?v];
  if (known.isEmpty) return (0, 1);
  final lo = known.reduce(math.min), hi = known.reduce(math.max);
  return (lo * .79, math.max(hi * 1.22, lo * .79 + 1));
}
