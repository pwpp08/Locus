// An A2UI surface in the coach's chat, drawn with the app's own pieces: the
// basic catalog's components (see `coach/coach_a2ui.dart`) as Locus text,
// cards, chips, switches and buttons on the coach's dark ground. Inputs write
// to the surface's own copy of its data model; a Button sends its action back
// to the coach as the person's next message.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../coach/coach_a2ui.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'coach_figures.dart' show chatDate;

/// A tap on a Button: the words for the person's bubble, and the A2UI
/// action message the coach reads.
typedef A2uiActionHandler = void Function(
    String said, Map<String, dynamic> message);

class A2uiSurfaceView extends StatefulWidget {
  /// The render spec `prepareA2ui` made: components, data model, surface id.
  final Map<String, dynamic> spec;
  final A2uiActionHandler? onAction;
  const A2uiSurfaceView({super.key, required this.spec, this.onAction});

  @override
  State<A2uiSurfaceView> createState() => _A2uiSurfaceViewState();
}

class _A2uiSurfaceViewState extends State<A2uiSurfaceView> {
  late final Map<String, Map<String, dynamic>> _byId = {
    for (final c in (widget.spec['components'] as List? ?? const []))
      if (c is Map && c['id'] is String)
        c['id'] as String: c.cast<String, dynamic>(),
  };

  // A copy: what the person types stays on this surface, and a saved chat
  // redraws what the coach sent.
  late Object? _data = _copy(widget.spec['dataModel']);
  final _tabs = <String, int>{};

  static Object? _copy(Object? v) => v is Map
      ? {for (final e in v.entries) '${e.key}': _copy(e.value)}
      : v is List
          ? [for (final e in v) _copy(e)]
          : v;

  void _write(String? path, Object? value) {
    if (path == null) return;
    setState(() => _data = a2uiSet(_data, path, value));
  }

  @override
  Widget build(BuildContext c) => _node(c, 'root', '/', 0);

  Widget _node(BuildContext c, String id, String scope, int depth) {
    final comp = _byId[id];
    // A loop of children (a list that contains itself) stops here.
    if (comp == null || depth > 24) return const SizedBox.shrink();
    final p = P.of(c);
    String text(String k) => a2uiText(comp[k], _data, scope: scope);
    List<Widget> kids() => [
          for (final (cid, s) in a2uiChildren(comp, _data, scope))
            _node(c, cid, s, depth + 1),
        ];
    Widget? child(String k) =>
        comp[k] is String ? _node(c, comp[k] as String, scope, depth + 1) : null;

    switch ('${comp['component']}') {
      case 'Text':
        return _Words(text('text'), '${comp['variant'] ?? comp['usageHint'] ?? 'body'}');
      case 'Icon':
        return Icon(_icon(text('name')), size: I.md, color: p.ink);
      case 'Image':
        final url = text('url');
        final uri = Uri.tryParse(url);
        // Only https: a model-written address is fetched by this phone.
        if (uri == null || uri.scheme != 'https') return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: R.rMd,
          child: Image.network(url,
              fit: BoxFit.cover,
              height: '${comp['variant']}' == 'icon' ? S.x8 : S.x16 * 2,
              errorBuilder: (_, _, _) => const SizedBox.shrink()),
        );
      case 'Divider':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Container(height: S.hair, color: p.line),
        );
      case 'Row':
        return _flex(comp, kids(), Axis.horizontal);
      case 'Column':
        return _flex(comp, kids(), Axis.vertical);
      case 'List':
        final horizontal = '${comp['direction']}' == 'horizontal';
        final items = kids();
        return horizontal
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: S.x2),
                    items[i],
                  ],
                ]),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: S.x2),
                  items[i],
                ],
              ]);
      case 'Card':
        return Container(
          padding: const EdgeInsets.all(S.x3),
          decoration: BoxDecoration(
            color: C.white.withValues(alpha: .06),
            borderRadius: R.rLg,
            border: Border.all(color: C.white.withValues(alpha: .08)),
          ),
          child: child('child') ?? const SizedBox.shrink(),
        );
      case 'Tabs':
        final tabs = [
          for (final t in (comp['tabs'] as List? ?? const []))
            if (t is Map) t,
        ];
        if (tabs.isEmpty) return const SizedBox.shrink();
        final at = (_tabs[id] ?? 0).clamp(0, tabs.length - 1);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SubTabs(
            [for (final t in tabs) a2uiText(t['title'], _data, scope: scope)],
            at,
            (i) => setState(() => _tabs[id] = i),
            color: C.white,
          ),
          const SizedBox(height: S.x3),
          if (tabs[at]['child'] is String)
            _node(c, tabs[at]['child'] as String, scope, depth + 1),
        ]);
      case 'Modal':
        final content = comp['content'];
        return Pressable(
          semanticLabel: 'More',
          onTap: content is! String
              ? null
              : () => AppSheet.show<void>(c,
                  child: _node(c, content, scope, depth + 1)),
          child: child('trigger') ?? const SizedBox.shrink(),
        );
      case 'Button':
        return _button(c, comp, scope, depth);
      case 'TextField':
        final path = a2uiPathOf(comp['value'], scope);
        final variant = '${comp['variant'] ?? comp['textFieldType'] ?? 'shortText'}';
        return AppField(
          label: text('label'),
          initialValue: text('value'),
          keyboardType: variant == 'number'
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          minLines: variant == 'longText' ? 3 : 1,
          maxLines: variant == 'longText' ? 6 : 1,
          onChanged: (v) => _write(
              path, variant == 'number' ? (num.tryParse(v) ?? v) : v),
        );
      case 'CheckBox':
        final path = a2uiPathOf(comp['value'], scope);
        final on = a2uiValue(comp['value'], _data, scope: scope) == true;
        return Pressable(
          semanticLabel: '${text('label')}, ${on ? 'checked' : 'not checked'}',
          onTap: () => _write(path, !on),
          child: SizedBox(
            height: S.tap,
            child: Row(children: [
              AnimatedContainer(
                duration: motion(c, Motion.fast),
                width: S.x6,
                height: S.x6,
                decoration: BoxDecoration(
                  color: on ? C.white : null,
                  borderRadius: R.rSm,
                  border: Border.all(
                      color: on ? C.white : p.ink3, width: S.half),
                ),
                child: on
                    ? const Icon(LucideIcons.check, size: I.sm, color: C.char)
                    : null,
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(text('label'),
                    style: F.body.copyWith(color: p.ink)),
              ),
            ]),
          ),
        );
      case 'ChoicePicker':
        return _choices(c, comp, scope);
      case 'Slider':
        final path = a2uiPathOf(comp['value'], scope);
        final lo = _num(a2uiValue(comp['min'] ?? comp['minValue'], _data, scope: scope)) ?? 0;
        final hi = _num(a2uiValue(comp['max'] ?? comp['maxValue'], _data, scope: scope)) ?? 100;
        final v = (_num(a2uiValue(comp['value'], _data, scope: scope)) ?? lo)
            .clamp(lo, hi <= lo ? lo + 1 : hi)
            .toDouble();
        return _A2uiSlider(
          label: text('label'),
          lo: lo.toDouble(),
          hi: hi <= lo ? lo + 1.0 : hi.toDouble(),
          value: v,
          onChanged: (x) => _write(path, x == x.roundToDouble() ? x.round() : x),
        );
      case 'DateTimeInput':
        return _dateTime(c, comp, scope);
    }
    return const SizedBox.shrink();
  }

  static num? _num(Object? v) => v is num ? v : num.tryParse('$v');

  Widget _flex(Map<String, dynamic> comp, List<Widget> kids, Axis axis) {
    final justify = switch ('${comp['justify'] ?? comp['distribution']}') {
      'center' => MainAxisAlignment.center,
      'end' => MainAxisAlignment.end,
      'spaceBetween' => MainAxisAlignment.spaceBetween,
      'spaceEvenly' => MainAxisAlignment.spaceEvenly,
      'spaceAround' => MainAxisAlignment.spaceAround,
      _ => MainAxisAlignment.start,
    };
    final align = switch ('${comp['align'] ?? comp['alignment']}') {
      'center' => CrossAxisAlignment.center,
      'end' => CrossAxisAlignment.end,
      'start' => CrossAxisAlignment.start,
      _ => axis == Axis.vertical
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
    };
    final gap = axis == Axis.vertical
        ? const SizedBox(height: S.x2)
        : const SizedBox(width: S.x2);
    final spaced = justify == MainAxisAlignment.start;
    final items = [
      for (var i = 0; i < kids.length; i++) ...[
        if (i > 0 && spaced) gap,
        // A row's words share its width rather than run off the card.
        axis == Axis.horizontal && justify == MainAxisAlignment.start
            ? Flexible(child: kids[i])
            : kids[i],
      ],
    ];
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: justify,
      crossAxisAlignment: align,
      children: items,
    );
  }

  Widget _button(
      BuildContext c, Map<String, dynamic> comp, String scope, int depth) {
    final variant = '${comp['variant'] ?? (comp['primary'] == true ? 'primary' : 'default')}';
    final label = comp['child'] is String
        ? _labelOf(comp['child'] as String, scope)
        : a2uiText(comp['label'], _data, scope: scope);
    final action = comp['action'];
    final call = action is Map ? action['functionCall'] : null;
    VoidCallback? onTap;
    if (call is Map && call['@call'] == 'openUrl') {
      final url = a2uiText((call['args'] as Map?)?['url'], _data, scope: scope);
      final uri = Uri.tryParse(url);
      if (uri != null && uri.scheme == 'https') {
        onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (widget.onAction != null) {
      onTap = () {
        final msg = a2uiActionMessage(
            spec: widget.spec,
            button: comp,
            data: _data,
            scope: scope,
            at: DateTime.now());
        final a = msg['action'] as Map<String, dynamic>;
        widget.onAction!('${a['userMessage'] ?? label}', msg);
      };
    }
    final primary = variant == 'primary';
    final borderless = variant == 'borderless';
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: S.tap),
        padding: const EdgeInsets.symmetric(horizontal: S.x4),
        alignment: Alignment.center,
        decoration: borderless
            ? null
            : BoxDecoration(
                color: primary ? C.white : C.white.withValues(alpha: .1),
                borderRadius: R.rPill,
              ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: F.body.copyWith(
                color: primary ? C.char : C.white,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// A Button's words: its child Text, read through.
  String _labelOf(String id, String scope) {
    final comp = _byId[id];
    if (comp == null) return '';
    if ('${comp['component']}' == 'Text') {
      return a2uiText(comp['text'], _data, scope: scope);
    }
    for (final (cid, s) in a2uiChildren(comp, _data, scope)) {
      final t = _labelOf(cid, s);
      if (t.isNotEmpty) return t;
    }
    return comp['child'] is String ? _labelOf(comp['child'] as String, scope) : '';
  }

  Widget _choices(BuildContext c, Map<String, dynamic> comp, String scope) {
    final p = P.of(c);
    final path = a2uiPathOf(comp['value'] ?? comp['selections'], scope);
    final many = '${comp['variant']}' == 'multipleSelection' ||
        (comp['maxAllowedSelections'] is num &&
            (comp['maxAllowedSelections'] as num) > 1);
    final raw = a2uiValue(comp['value'] ?? comp['selections'], _data, scope: scope);
    final picked = <String>{
      if (raw is List) for (final v in raw) '$v' else if (raw != null) '$raw',
    };
    final options = [
      for (final o in (comp['options'] as List? ?? const []))
        if (o is Map)
          (
            label: a2uiText(o['label'], _data, scope: scope),
            value: '${a2uiValue(o['value'], _data, scope: scope)}',
          ),
    ];
    final label = a2uiText(comp['label'], _data, scope: scope);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty) ...[
        Text(label, style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(height: S.x2),
      ],
      Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        for (final o in options)
          Pressable(
            semanticLabel:
                '${o.label}, ${picked.contains(o.value) ? 'chosen' : 'not chosen'}',
            onTap: () {
              final next = many
                  ? (picked.contains(o.value)
                      ? (picked.toList()..remove(o.value))
                      : [...picked, o.value])
                  : [o.value];
              _write(path, many ? next : (raw is List ? next : o.value));
            },
            child: AnimatedContainer(
              duration: motion(c, Motion.fast),
              constraints: const BoxConstraints(minHeight: S.tap - S.x2),
              padding: const EdgeInsets.symmetric(
                  horizontal: S.x4, vertical: S.x2),
              decoration: BoxDecoration(
                color: picked.contains(o.value)
                    ? C.white
                    : C.white.withValues(alpha: .08),
                borderRadius: R.rPill,
              ),
              child: Text(o.label,
                  style: F.body.copyWith(
                      color: picked.contains(o.value) ? C.char : C.white,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    ]);
  }

  Widget _dateTime(BuildContext c, Map<String, dynamic> comp, String scope) {
    final p = P.of(c);
    final path = a2uiPathOf(comp['value'], scope);
    final wantDate = comp['enableDate'] != false;
    final wantTime = comp['enableTime'] == true;
    final now = a2uiText(comp['value'], _data, scope: scope);
    final label = a2uiText(comp['label'], _data, scope: scope);
    Future<void> pick() async {
      final was = DateTime.tryParse(now) ?? DateTime.now();
      var at = was;
      if (wantDate) {
        final d = await pickDate(c,
            initial: was,
            first: DateTime(was.year - 5),
            last: DateTime(was.year + 5));
        if (d == null) return;
        at = DateTime(d.year, d.month, d.day, at.hour, at.minute);
      }
      if (wantTime && c.mounted) {
        final t = await pickTime(c,
            initial: TimeOfDay(hour: at.hour, minute: at.minute));
        if (t == null) return;
        at = DateTime(at.year, at.month, at.day, t.hour, t.minute);
      }
      final iso = at.toIso8601String();
      _write(path, wantTime ? iso.substring(0, 16) : iso.substring(0, 10));
    }

    return Pressable(
      semanticLabel: '$label ${now.isEmpty ? 'not set' : now}',
      onTap: pick,
      child: Container(
        height: S.tap,
        padding: const EdgeInsets.symmetric(horizontal: S.x3),
        decoration: BoxDecoration(
            color: C.white.withValues(alpha: .06), borderRadius: R.rMd),
        child: Row(children: [
          Icon(wantDate ? LucideIcons.calendar : LucideIcons.clock,
              size: I.md, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(label, style: F.body.copyWith(color: p.ink2)),
          ),
          Text(_shown(now, wantTime),
              style: F.num(F.body).copyWith(color: p.ink)),
        ]),
      ),
    );
  }

  /// A picked value as words: "Tue 24 Nov", "Tue 24 Nov, 18:30".
  String _shown(String iso, bool time) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso.isEmpty ? 'Choose' : iso;
    final day =
        chatDate(d, now: DateTime.now(), l: AppLocalizations.of(context));
    if (!time || !iso.contains('T')) return day;
    return '$day, ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  static IconData _icon(String name) => switch (name
      .replaceAll(RegExp(r'[_\-\s]'), '')
      .toLowerCase()) {
    'check' || 'done' || 'checkcircle' => LucideIcons.check,
    'close' || 'x' || 'cancel' => LucideIcons.x,
    'info' => LucideIcons.info,
    'warning' || 'error' => LucideIcons.triangleAlert,
    'star' || 'favorite' => LucideIcons.star,
    'heart' => LucideIcons.heart,
    'moon' || 'sleep' || 'night' => LucideIcons.moon,
    'sun' || 'day' => LucideIcons.sun,
    'bolt' || 'zap' || 'energy' => LucideIcons.zap,
    'calendar' || 'calendartoday' || 'event' => LucideIcons.calendar,
    'clock' || 'time' || 'schedule' => LucideIcons.clock,
    'run' || 'directionsrun' || 'activity' => LucideIcons.activity,
    'bike' || 'directionsbike' => LucideIcons.bike,
    'walk' || 'directionswalk' => LucideIcons.footprints,
    'water' || 'drop' => LucideIcons.droplet,
    'food' || 'restaurant' || 'meal' => LucideIcons.utensils,
    'bed' || 'hotel' => LucideIcons.bed,
    'timer' => LucideIcons.timer,
    'trophy' => LucideIcons.trophy,
    'flame' || 'fire' => LucideIcons.flame,
    'search' => LucideIcons.search,
    'arrowforward' || 'chevronright' => LucideIcons.chevronRight,
    _ => LucideIcons.circle,
  };
}

/// A Text component: its variant as a size, `**bold**` read through.
class _Words extends StatelessWidget {
  final String text;
  final String variant;
  const _Words(this.text, this.variant);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final style = switch (variant) {
      'h1' => F.t1.copyWith(color: p.ink),
      'h2' => F.t2.copyWith(color: p.ink),
      'h3' => F.head.copyWith(color: p.ink),
      'h4' => F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700),
      'h5' => F.caps.copyWith(color: p.ink2),
      'caption' => F.cap.copyWith(color: p.ink3),
      _ => F.body.copyWith(color: p.ink, height: 1.4),
    };
    final parts = text.split('**');
    return Text.rich(TextSpan(style: style, children: [
      for (var i = 0; i < parts.length; i++)
        TextSpan(
            text: parts[i],
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null),
    ]));
  }
}

/// A Slider component: the value over a track the finger drags along.
class _A2uiSlider extends StatelessWidget {
  final String label;
  final double lo, hi, value;
  final ValueChanged<double> onChanged;
  const _A2uiSlider({
    required this.label,
    required this.lo,
    required this.hi,
    required this.value,
    required this.onChanged,
  });

  String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // Whole steps when the range is whole numbers.
    final whole = lo == lo.roundToDouble() && hi == hi.roundToDouble();
    final frac = ((value - lo) / (hi - lo)).clamp(0.0, 1.0);
    double at(double f) {
      final v = lo + f.clamp(0.0, 1.0) * (hi - lo);
      return whole ? v.roundToDouble() : v;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(label, style: F.cap.copyWith(color: p.ink2)),
        ),
        Text(_fmt(value),
            style: F.num(F.body)
                .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
      ]),
      // Scrubber carries the drag, the 44 pt strip and the slider semantics.
      Scrubber(
        value: frac,
        label: label,
        describe: (f) => _fmt(at(f)),
        step: whole ? (1 / (hi - lo)).clamp(.05, 1.0) : .05,
        onChanged: (f) => onChanged(at(f)),
        child: SizedBox(
          height: S.tap,
          child: LayoutBuilder(
            builder: (c, box) => Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: S.x1,
                    decoration: BoxDecoration(
                        color: p.track, borderRadius: R.rPill),
                  ),
                  Container(
                    width: frac * box.maxWidth,
                    height: S.x1,
                    decoration: const BoxDecoration(
                        color: C.white, borderRadius: R.rPill),
                  ),
                  Positioned(
                    left: (frac * box.maxWidth - S.x3)
                        .clamp(0.0, box.maxWidth - S.x6),
                    child: Container(
                      width: S.x6,
                      height: S.x6,
                      decoration: const BoxDecoration(
                          color: C.white, shape: BoxShape.circle),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    ]);
  }
}
