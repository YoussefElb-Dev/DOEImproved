import 'package:flutter/services.dart';

/// Native bridge to the platform WebView cookie jar (Android CookieManager,
/// iOS WKHTTPCookieStore). Reads the FULL cookie set including HttpOnly
/// cookies that are invisible to document.cookie.
class NativeCookieBridge {
  NativeCookieBridge._();
  static const _channel = MethodChannel('doe_improved/cookies');

  /// Returns all cookies for [url] as a name→value map.
  /// Falls back to an empty map if the platform call is unavailable.
  static Future<Map<String, String>> getCookies(String url) async {
    try {
      final result = await _channel.invokeMapMethod<String, String>(
        'getCookies',
        {'url': url},
      );
      return result ?? const {};
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  static Future<bool> clearCookies() async {
    try {
      return await _channel.invokeMethod<bool>('clearCookies') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Serializes cookies into an HTTP Cookie header value.
  static String toHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}