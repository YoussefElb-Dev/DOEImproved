import 'package:flutter/services.dart';

/// The DOE properties this app talks to.
///
/// Two hosts, because grades and documents live in different places:
/// TeachHub serves the gradebook, and nycenet.edu serves the PDFs — the
/// transcript and report cards.
class PortalHosts {
  PortalHosts._();

  static const String teachHub = 'teachhub.schools.nyc';
  static const String documents = 'www.nycenet.edu';

  static const List<String> all = [teachHub, documents];

  /// Whether a request may carry the session. Anything outside these domains
  /// is refused so the cookie cannot leak off DOE property.
  static bool isAllowed(String host) {
    final h = host.toLowerCase();
    return h.endsWith('schools.nyc') || h.endsWith('nycenet.edu');
  }
}

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

  /// Cookies are stored with their host in the key — `host|name` — so the
  /// session for one DOE property is never sent to another. A key with no
  /// host belongs to TeachHub, which is where sessions saved by earlier
  /// versions came from.
  static String scopedKey(String host, String name) => '$host|$name';

  /// Serialises the cookies that belong to [host] into a Cookie header.
  /// Passing no host returns everything, which only the tests do.
  static String toHeader(Map<String, String> cookies, {String? host}) {
    final parts = <String>[];
    cookies.forEach((key, value) {
      final separator = key.indexOf('|');
      if (separator < 0) {
        if (host == null || host.toLowerCase().endsWith('schools.nyc')) {
          parts.add('$key=$value');
        }
        return;
      }
      final scope = key.substring(0, separator).toLowerCase();
      final name = key.substring(separator + 1);
      if (host == null || host.toLowerCase().endsWith(_registrable(scope))) {
        parts.add('$name=$value');
      }
    });
    return parts.join('; ');
  }

  /// `www.nycenet.edu` → `nycenet.edu`, so a cookie captured on the www host
  /// is still sent to the bare domain and vice versa.
  static String _registrable(String host) {
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    return labels.sublist(labels.length - 2).join('.');
  }
}
