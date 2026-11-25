// The Zepp sign-in WebView's cookies, through the small Android channel in
// `NativeChannels.kt`. Android only: elsewhere the channel is missing and the
// reads return null, so the sign-in screen falls back to typing the key.

import 'package:flutter/services.dart';

import 'zepp_cloud.dart' show kZeppCookieUrls;

const MethodChannel _channel = MethodChannel('openstrap/zepp_cookies');

/// The cookies the sign-in pages would send, joined into one header, or null
/// when there are none or the channel is not there.
Future<String?> readZeppCookieHeader() async {
  final parts = <String>[];
  for (final url in kZeppCookieUrls) {
    try {
      final c = await _channel.invokeMethod<String>('get', {'url': url});
      if (c != null && c.isNotEmpty) parts.add(c);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      continue;
    }
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// Forgets every cookie in the WebView, so the sign-in does not outlive its one
/// use.
Future<void> clearZeppCookies() async {
  try {
    await _channel.invokeMethod<void>('clear');
  } on MissingPluginException {
    // Nothing to clear off Android.
  } on PlatformException {
    // Best effort.
  }
}
