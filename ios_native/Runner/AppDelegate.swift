import Flutter
import UIKit
import WebKit

/// Hosts the `doe_improved/cookies` platform channel.
///
/// The TeachHub SSO session cookies are HttpOnly, so `document.cookie` inside
/// the WebView cannot see them. Reading `WKWebsiteDataStore`'s cookie store
/// natively is the only way to obtain a session usable for HTTP requests.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let cookieChannel = "doe_improved/cookies"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: AppDelegate.cookieChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getCookies":
          guard
            let args = call.arguments as? [String: Any],
            let raw = args["url"] as? String,
            let host = URL(string: raw)?.host
          else {
            result(FlutterError(
              code: "ARG_NULL",
              message: "Missing or invalid 'url' argument",
              details: nil
            ))
            return
          }
          AppDelegate.readCookies(forHost: host, result: result)
        case "clearCookies":
          AppDelegate.clearAllData(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Returns every cookie in the WKWebView jar scoped to `host`, including
  /// HttpOnly ones. Must run on the main thread — WKHTTPCookieStore requires it.
  private static func readCookies(forHost host: String, result: @escaping FlutterResult) {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
      var map: [String: String] = [:]
      for cookie in cookies where AppDelegate.domain(cookie.domain, covers: host) {
        map[cookie.name] = cookie.value
      }
      result(map)
    }
  }

  /// Cookie domains are either host-scoped ("teachhub.schools.nyc") or
  /// domain-scoped with a leading dot (".schools.nyc"), which covers subdomains.
  private static func domain(_ cookieDomain: String, covers host: String) -> Bool {
    let base = cookieDomain.hasPrefix(".")
      ? String(cookieDomain.dropFirst())
      : cookieDomain
    return host == base || host.hasSuffix("." + base)
  }

  /// Clears cookies plus cached site data, so signing out really signs out.
  private static func clearAllData(result: @escaping FlutterResult) {
    let store = WKWebsiteDataStore.default()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    store.fetchDataRecords(ofTypes: types) { records in
      store.removeData(ofTypes: types, for: records) {
        result(true)
      }
    }
  }
}
