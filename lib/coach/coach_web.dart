// The coach's window on the web: a search, and reading one page.
//
// Two ways to search, picked by the provider the person already set up:
// - a Google Gemini key searches with Google, through Gemini's own search
//   grounding (one extra call on the same key, an answer plus its sources);
// - anything else, or a Gemini search that fails, reads DuckDuckGo's plain
//   HTML results, which needs no key at all.
//
// What leaves the phone is the query the model wrote and nothing else. The
// prompt tells it to keep that generic ("VO2 max norms men 18-25"), never the
// person's name or their own numbers.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'coach_config.dart';

/// The most of one page the model is handed.
const int kWebPageChars = 12000;

/// How many results a keyless search returns.
const int kWebResults = 6;

class CoachWeb {
  CoachWeb._();

  static const _agent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Mobile Safari/537.36';

  static const _timeout = Duration(seconds: 25);

  /// Whether [apiBase] is Google's Gemini endpoint.
  static bool isGemini(String apiBase) =>
      Uri.tryParse(apiBase)?.host == 'generativelanguage.googleapis.com';

  /// Search the web for [query]. Never throws: a failure comes back as a
  /// sentence the model can act on.
  static Future<String> search(
    String query, {
    required CoachConfig config,
    http.Client? client,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return 'Give a search query.';
    final c = client ?? http.Client();
    try {
      if (isGemini(config.apiBase) && config.hasKey) {
        try {
          final g = await _gemini(q, config, c);
          if (g != null) return g;
        } catch (_) {/* fall through to the keyless search */}
      }
      return await _duckDuckGo(q, c);
    } catch (e) {
      return 'The web search did not go through ($e). Answer without it and '
          'say so.';
    } finally {
      if (client == null) c.close();
    }
  }

  /// Gemini with Google Search grounding: an answer written from the results,
  /// and the pages it came from.
  static Future<String?> _gemini(
      String q, CoachConfig config, http.Client c) async {
    var model = config.model.trim();
    if (model.isEmpty) return null;
    if (!model.startsWith('models/')) model = 'models/$model';
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/$model:generateContent');
    final resp = await c
        .post(uri,
            headers: {
              'x-goog-api-key': config.apiKey ?? '',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'text': 'Search the web and report what reliable sources '
                          'say, with the exact figures, tables and ranges they '
                          'give, and who says it. Plain text, no advice.\n\n'
                          'Search: $q',
                    },
                  ],
                },
              ],
              'tools': [
                {'google_search': {}},
              ],
            }))
        .timeout(_timeout);
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(resp.bodyBytes));
    if (j is! Map) return null;
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty || cands.first is! Map) return null;
    final cand = cands.first as Map;
    final parts = (cand['content'] as Map?)?['parts'];
    final text = parts is List
        ? parts
            .map((p) => p is Map ? '${p['text'] ?? ''}' : '')
            .join()
            .trim()
        : '';
    if (text.isEmpty) return null;
    final sources = <String>[];
    final chunks = (cand['groundingMetadata'] as Map?)?['groundingChunks'];
    if (chunks is List) {
      for (final ch in chunks) {
        final web = ch is Map ? ch['web'] : null;
        if (web is Map && web['uri'] != null) {
          sources.add('${web['title'] ?? 'source'} — ${web['uri']}');
        }
      }
    }
    return [
      'WEB SEARCH (Google) for "$q":',
      text,
      if (sources.isNotEmpty) 'Sources:',
      for (var i = 0; i < sources.length && i < 8; i++) '${i + 1}. ${sources[i]}',
    ].join('\n');
  }

  /// DuckDuckGo's HTML results page: titles, links and snippets.
  static Future<String> _duckDuckGo(String q, http.Client c) async {
    final resp = await c
        .post(Uri.parse('https://html.duckduckgo.com/html/'),
            headers: {
              'user-agent': _agent,
              'content-type': 'application/x-www-form-urlencoded',
            },
            body: {'q': q})
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      return 'The web search answered ${resp.statusCode}. Answer without it '
          'and say so.';
    }
    final results = parseDuckDuckGo(utf8.decode(resp.bodyBytes,
        allowMalformed: true));
    if (results.isEmpty) {
      return 'The web search for "$q" found nothing. Try other words once, '
          'or answer without it and say so.';
    }
    return [
      'WEB SEARCH for "$q" (read a page with read_web_page for more than the '
          'snippet):',
      for (var i = 0; i < results.length; i++)
        '${i + 1}. ${results[i].title} — ${results[i].url}\n'
            '   ${results[i].snippet}',
    ].join('\n');
  }

  /// The results on a DuckDuckGo HTML page. Public for tests.
  static List<({String title, String url, String snippet})> parseDuckDuckGo(
      String html) {
    final out = <({String title, String url, String snippet})>[];
    final link = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>');
    final snip = RegExp(r'class="result__snippet"[^>]*>([\s\S]*?)</a>');
    final links = link.allMatches(html).toList();
    final snips = snip.allMatches(html).toList();
    for (var i = 0; i < links.length && out.length < kWebResults; i++) {
      final url = _realUrl(_entities(links[i].group(1)!));
      if (url == null || url.contains('duckduckgo.com/y.js')) continue;
      out.add((
        title: _text(links[i].group(2)!),
        url: url,
        snippet: i < snips.length ? _text(snips[i].group(1)!) : '',
      ));
    }
    return out;
  }

  /// DuckDuckGo wraps each link in a redirect carrying it as `uddg`.
  static String? _realUrl(String href) {
    final abs = href.startsWith('//') ? 'https:$href' : href;
    final u = Uri.tryParse(abs);
    if (u == null) return null;
    final wrapped = u.queryParameters['uddg'];
    if (wrapped != null && wrapped.isNotEmpty) return wrapped;
    return u.hasScheme ? abs : null;
  }

  /// Read one web page as text: scripts, styles and tags stripped, cut at
  /// [kWebPageChars]. Only public http(s) addresses.
  static Future<String> readPage(String url, {http.Client? client}) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) {
      return 'That is not a web address.';
    }
    if (_privateHost(u.host)) return 'Only public web pages can be read.';
    final c = client ?? http.Client();
    try {
      final resp = await c
          .get(u, headers: {'user-agent': _agent, 'accept': 'text/html,*/*'})
          .timeout(_timeout);
      if (resp.statusCode != 200) {
        return 'The page answered ${resp.statusCode}.';
      }
      final type = resp.headers['content-type'] ?? '';
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final text = type.contains('html') || body.trimLeft().startsWith('<')
          ? pageText(body)
          : body.trim();
      if (text.isEmpty) return 'The page has no readable text.';
      return text.length <= kWebPageChars
          ? 'PAGE $url:\n$text'
          : 'PAGE $url (first $kWebPageChars characters):\n'
              '${text.substring(0, kWebPageChars)}…';
    } catch (e) {
      return 'The page could not be read ($e).';
    } finally {
      if (client == null) c.close();
    }
  }

  /// A page's readable text: no scripts, styles, navigation or tags, one
  /// line per block. Public for tests.
  static String pageText(String html) {
    var s = html.replaceAll(
        RegExp(r'<(script|style|noscript|svg|nav|footer|header|form)\b[\s\S]*?</\1>',
            caseSensitive: false),
        ' ');
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    s = s.replaceAll(
        RegExp(r'<(br|/p|/div|/li|/tr|/h[1-6]|/section|/article)\b[^>]*>',
            caseSensitive: false),
        '\n');
    s = s.replaceAll(RegExp(r'<(td|th)\b[^>]*>', caseSensitive: false), ' | ');
    s = _entities(s.replaceAll(RegExp(r'<[^>]+>'), ' '));
    final lines = s
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim())
        .where((l) => l.isNotEmpty && l != '|');
    return lines.join('\n');
  }

  static String _text(String html) =>
      _entities(html.replaceAll(RegExp(r'<[^>]+>'), ''))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  static String _entities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)));

  static bool _privateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.localhost')) {
      return true;
    }
    final ip = RegExp(r'^(\d+)\.(\d+)\.\d+\.\d+$').firstMatch(h);
    if (ip == null) return h == '::1' || h.startsWith('[');
    final a = int.parse(ip.group(1)!), b = int.parse(ip.group(2)!);
    return a == 10 ||
        a == 127 ||
        a == 0 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 100 && b >= 64 && b <= 127);
  }
}
