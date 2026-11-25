import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstrap_edge/ble/helio/zepp_cloud.dart';

const _key = '00112233445566778899aabbccddeeff';

String _list(List<Map<String, Object?>> items) => jsonEncode({'items': items});

void main() {
  group('session from cookies', () {
    test('the login-info blob, once and twice encoded', () {
      final j = jsonEncode({
        'token_info': {'app_token': 'tok', 'user_id': '42', 'login_token': 'x'}
      });
      for (final c in [Uri.encodeComponent(j), Uri.encodeComponent(Uri.encodeComponent(j))]) {
        final s = zeppSessionFromCookies('a=b; hm-user-login-info=$c; z=1')!;
        expect((s.userId, s.appToken), ('42', 'tok'));
      }
    });

    test('plain apptoken and userid cookies', () {
      final s = zeppSessionFromCookies('apptoken=T; userid=7')!;
      expect((s.userId, s.appToken), ('7', 'T'));
    });

    test('nothing yet is null, not a crash', () {
      expect(zeppSessionFromCookies(null), isNull);
      expect(zeppSessionFromCookies(''), isNull);
      expect(zeppSessionFromCookies('a=b'), isNull);
      expect(zeppSessionFromCookies('hm-user-login-info=%7Bnot json'), isNull);
    });
  });

  group('device list', () {
    test('items, an additionalInfo string and an object, and the pick', () {
      final body = _list([
        {
          'macAddress': 'aa:bb:cc:dd:ee:01',
          'deviceSource': 10289410,
          'productId': 157,
          'bindingStatus': 0,
          'additionalInfo': jsonEncode({'auth_key': _key, 'sn': 'SN1'}),
        },
        {
          'macAddress': 'AA:BB:CC:DD:EE:02',
          'deviceSource': 10289411,
          'bindingStatus': 1,
          'activeStatus': 1,
          'additionalInfo': {'auth_key': '0x$_key', 'hardwareVersion': 'H2'},
        },
        {'macAddress': 'AA:BB:CC:DD:EE:03', 'deviceSource': 5},
      ]);
      final all = parseZeppDevices(body);
      expect(all.length, 3);
      expect(all[0].mac, 'AA:BB:CC:DD:EE:01');
      expect(all[0].key, isNotNull);
      expect(all[0].serial, 'SN1');
      expect(all[1].hardware, 'H2');
      expect(all[2].isHelio, isFalse);
      // Both have keys; the bound, active one wins.
      expect(pickHelioStrap(all)!.mac, 'AA:BB:CC:DD:EE:02');
    });

    test('a bad MAC is dropped and a bad key is ignored', () {
      final all = parseZeppDevices(_list([
        {'macAddress': 'nope', 'deviceSource': 10289410},
        {
          'macAddress': 'AA:BB:CC:DD:EE:09',
          'deviceSource': 10289410,
          'additionalInfo': {'auth_key': 'zz'},
        },
      ]));
      expect(all.length, 1);
      expect(all.single.key, isNull);
    });

    test('empty list and no Helio', () {
      expect(parseZeppDevices(_list([])), isEmpty);
      expect(pickHelioStrap([]), isNull);
      expect(pickHelioStrap(parseZeppDevices(_list([{'macAddress': 'AA:BB:CC:DD:EE:09', 'deviceSource': 1}]))), isNull);
    });

    test('a body that is not the list is refused, not read as empty', () {
      expect(() => parseZeppDevices('<html>'), throwsFormatException);
      expect(() => parseZeppDevices('{"code":1}'), throwsFormatException);
    });
  });

  group('lookup', () {
    const s = ZeppSession(userId: '42', appToken: 'tok');
    final good = _list([
      {'macAddress': 'AA:BB:CC:DD:EE:01', 'deviceSource': 10289410, 'additionalInfo': {'auth_key': _key}}
    ]);

    test('moves past a region that rejects the token', () async {
      final hosts = <String>[];
      final z = ZeppCloud(client: MockClient((r) async {
        hosts.add(r.url.host);
        expect(r.headers['apptoken'], 'tok');
        return r.url.host == 'api-mifit-us2.zepp.com'
            ? http.Response(good, 200)
            : http.Response('no', 401);
      }));
      final out = await z.listDevices(s);
      expect(out.single.mac, 'AA:BB:CC:DD:EE:01');
      expect(hosts, ['api-mifit.zepp.com', 'api-mifit-us2.zepp.com']);
    });

    test('every region rejecting is a rejected session', () async {
      final z = ZeppCloud(client: MockClient((_) async => http.Response('no', 403)));
      await expectLater(z.listDevices(s),
          throwsA(isA<ZeppCloudException>().having((e) => e.kind, 'kind', ZeppFailure.rejected)));
    });

    test('no network is unreachable', () async {
      final z = ZeppCloud(client: MockClient((_) async => throw Exception('offline')));
      await expectLater(z.listDevices(s),
          throwsA(isA<ZeppCloudException>().having((e) => e.kind, 'kind', ZeppFailure.unreachable)));
    });
  });
}
