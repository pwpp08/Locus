// The coach's web search parsing, its memory, and the outlook's text folding.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ai/briefing.dart';
import 'package:openstrap_edge/ai/briefing_engine.dart';
import 'package:openstrap_edge/coach/coach_memory.dart';
import 'package:openstrap_edge/coach/coach_web.dart';
import 'package:openstrap_edge/ui2/screens/coach_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('web', () {
    test('DuckDuckGo results unwrap to the real address', () {
      const html = '''
<div class="result">
  <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.org%2Fvo2-norms&amp;rut=x">VO<b>2</b> max norms &amp; percentiles</a>
  <a class="result__snippet" href="#">For men aged 18&#39;s group, <b>52</b> is the 80th percentile.</a>
</div>
<div class="result">
  <a class="result__a" href="https://duckduckgo.com/y.js?ad=1">An ad</a>
  <a class="result__snippet">ad</a>
</div>''';
      final r = CoachWeb.parseDuckDuckGo(html);
      expect(r, hasLength(1));
      expect(r.single.url, 'https://example.org/vo2-norms');
      expect(r.single.title, 'VO2 max norms & percentiles');
      expect(r.single.snippet, contains("18's group, 52 is"));
    });

    test('a page reads as its text, without scripts or tags', () {
      final t = CoachWeb.pageText(
          '<html><head><style>p{}</style><script>var x=1</script></head>'
          '<body><nav>Menu</nav><h1>VO2 max</h1><p>Men 18-25: '
          '<b>42-46</b> is average.</p><table><tr><td>Age</td><td>Good</td>'
          '</tr></table></body></html>');
      expect(t, isNot(contains('var x')));
      expect(t, isNot(contains('Menu')));
      expect(t, contains('VO2 max'));
      expect(t, contains('Men 18-25: 42-46 is average.'));
      expect(t, contains('Age | Good'));
    });

    test('only public pages are read', () async {
      expect(await CoachWeb.readPage('http://192.168.1.4/admin'),
          contains('Only public'));
      expect(await CoachWeb.readPage('file:///etc/passwd'),
          contains('not a web address'));
    });

    test('Gemini is told apart by its host', () {
      expect(
          CoachWeb.isGemini(
              'https://generativelanguage.googleapis.com/v1beta/openai'),
          isTrue);
      expect(CoachWeb.isGemini('https://api.openai.com/v1'), isFalse);
    });
  });

  group('memory', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a note is kept once, and forgotten by its words', () async {
      await CoachMemory.add('No emojis in replies.');
      await CoachMemory.add('  no emojis in replies. ');
      await CoachMemory.add('Training for a half marathon in April.');
      expect(await CoachMemory.all(), [
        'no emojis in replies.',
        'Training for a half marathon in April.',
      ]);
      expect(await CoachMemory.forget('marathon'),
          ['Training for a half marathon in April.']);
      expect(await CoachMemory.all(), ['no emojis in replies.']);
    });

    test('the outlook follows the notes', () {
      final sys = briefingSystemPrompt(BriefingPeriod.morning,
          notes: const ['No emojis.']);
      expect(sys, contains('WHAT THEY ASKED YOU TO REMEMBER'));
      expect(sys, contains('- No emojis.'));
      expect(briefingSystemPrompt(BriefingPeriod.morning),
          isNot(contains('REMEMBER')));
    });

    test('each length asks for a different amount', () {
      final short = briefingSystemPrompt(BriefingPeriod.morning,
          length: OutlookLength.short);
      final long = briefingSystemPrompt(BriefingPeriod.morning,
          length: OutlookLength.detailed);
      expect(short, contains('90-130 words'));
      expect(long, contains('400-550 words'));
    });
  });

  test('paragraphs fold to single line breaks, code and tables kept', () {
    expect(tightParagraphs('Hi,\n\nHappy Monday!\n\n\n- one\n- two'),
        'Hi,\nHappy Monday!\n- one\n- two');
    expect(tightParagraphs('Text\n\n| a | b |\n|---|---|'),
        'Text\n\n| a | b |\n|---|---|');
    expect(tightParagraphs('```\na\n\nb\n```'), '```\na\n\nb\n```');
  });
}
