import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the hand-written iOS sources.
///
/// `ios/` is generated at build time and these files are copied over it, so a
/// mistake here is invisible until the app is installed on a device — the
/// symptom is a blank login page or a crash on picking a photo, neither of
/// which points at a plist. CI greps for the same things; this catches it
/// before a push.
void main() {
  final plist = File('ios_native/Runner/Info.plist');
  final appDelegate = File('ios_native/Runner/AppDelegate.swift');

  group('Info.plist', () {
    late String contents;

    setUpAll(() {
      expect(plist.existsSync(), isTrue, reason: '${plist.path} is missing');
      contents = plist.readAsStringSync();
    });

    test('is well-formed enough to be a plist', () {
      expect(contents, startsWith('<?xml'));
      expect(contents, contains('<!DOCTYPE plist'));
      expect(contents.trimRight(), endsWith('</plist>'));
    });

    test('allows the document site through App Transport Security', () {
      // www.nycenet.edu offers no forward-secrecy ciphers, so iOS refuses the
      // connection outright without this. Losing it breaks the transcript
      // download with an unexplained TLS error.
      expect(contents, contains('NSAppTransportSecurity'));
      expect(contents, contains('NSExceptionDomains'));
      expect(contents, contains('nycenet.edu'));
      expect(contents, contains('NSExceptionRequiresForwardSecrecy'));
    });

    test('keeps TLS 1.2 as the floor for that exception', () {
      // The server does support TLS 1.2; only forward secrecy needed relaxing.
      expect(contents, contains('<string>TLSv1.2</string>'));
      expect(contents, isNot(contains('TLSv1.0')));
      expect(contents, isNot(contains('TLSv1.1')));
    });

    test('never disables App Transport Security globally', () {
      // The key element, not the word — the plist names it in a comment
      // explaining why it is absent, and that must not read as a failure.
      expect(
        contents,
        isNot(contains('<key>NSAllowsArbitraryLoads</key>')),
        reason: 'one awkward host must not cost every other host its security',
      );
    });

    test('declares why it wants the photo library', () {
      // file_picker's image mode opens the system picker; iOS terminates the
      // app if this string is absent.
      expect(contents, contains('NSPhotoLibraryUsageDescription'));
    });

    test('carries the app name and orientations', () {
      expect(contents, contains('CFBundleDisplayName'));
      expect(contents, contains('Gradly'));
      expect(contents, contains('UILaunchStoryboardName'));
    });
  });

  group('AppDelegate.swift', () {
    late String contents;

    setUpAll(() {
      expect(appDelegate.existsSync(), isTrue,
          reason: '${appDelegate.path} is missing');
      contents = appDelegate.readAsStringSync();
    });

    test('hosts the cookie channel the session depends on', () {
      // Without this the SSO cookies are unreachable and live data never loads.
      expect(contents, contains('doe_improved/cookies'));
      expect(contents, contains('WKWebsiteDataStore'));
      expect(contents, contains('httpCookieStore'));
      expect(contents, contains('getCookies'));
      expect(contents, contains('clearCookies'));
    });

    test('registers the Flutter plugins', () {
      expect(contents, contains('GeneratedPluginRegistrant.register'));
    });
  });
}
