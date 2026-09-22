// Audit C: subscription tokens must never leave the process via Sentry.
//
// Log lines embed full subscription URLs (with private ?token=…); the scrub
// helper is the single choke point applied in SentryLoggyIntegration before
// any message becomes a breadcrumb/event payload.
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/sentry_utils.dart';

void main() {
  group('scrubSensitiveUrls', () {
    test('strips query string of subscription url with token', () {
      const input = 'subscription restored from [https://panel.example.com/sub?token=SECRET123]';
      expect(scrubSensitiveUrls(input), 'subscription restored from [https://panel.example.com/sub?…]');
    });

    test('strips query string of deep link import url', () {
      const input = 'hiddify import via https://cpdd.one/sub?token=abc&flag=1 done';
      expect(scrubSensitiveUrls(input), 'hiddify import via https://cpdd.one/sub?… done');
    });

    test('leaves urls without query strings untouched', () {
      const input = 'fetching https://example.com/plain';
      expect(scrubSensitiveUrls(input), input);
    });

    test('leaves non-url text untouched', () {
      const input = 'core started in 5.05s, no urls here';
      expect(scrubSensitiveUrls(input), input);
    });

    test('scrubs every url occurrence in one line', () {
      const input = 'a=https://x.io/sub?token=1 b=https://y.io/sub?token=2';
      expect(scrubSensitiveUrls(input), 'a=https://x.io/sub?… b=https://y.io/sub?…');
    });

    test('handles malformed trailing question mark', () {
      const input = 'url is https://example.com/sub?';
      expect(scrubSensitiveUrls(input), 'url is https://example.com/sub?…');
    });
  });
}
