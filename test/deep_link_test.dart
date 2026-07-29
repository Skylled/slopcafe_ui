// Unit tests for inbound web links — a tap on a public document URL anywhere
// on the device opening that document in the Reader.
//
// Two things carry this feature, and neither is visible from the Dart side at
// runtime:
//
//   - WHAT THE PARSER CLAIMS. The app is handed a URL by the OS and has to say
//     which document it addresses, or that it addresses none. Over-claiming
//     black-holes a link the operator meant for their browser; under-claiming
//     drops one they meant for the app. The matrix below pins both edges.
//   - THAT THE TWO CONFIGURED HOSTS AGREE. The domain is necessarily written
//     twice — once in Gradle, where it is compiled into the manifest filter
//     that decides whether Android *offers* the app the tap, and once in Dart,
//     where it decides whether the app *accepts* it. A mismatch is silent and
//     total: every link opens the app to nothing at all. The invariant test at
//     the bottom reads the literal back out of the build file so the pair
//     cannot drift, which is what makes "change the domain in one obvious
//     place" safe to promise an adopter.
//
// Hermetic: the parser is a pure function over `Uri`, and the config check
// reads files off disk. Nothing here touches the platform channel.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/deep_link.dart';

void main() {
  group('parseDeepLink — claimed', () {
    test('a /d/ link resolves to its public_id', () {
      final target = parseDeepLink(
        Uri.parse('https://$kDeepLinkHost/d/abc123'),
      );
      expect(target, const DeepLinkTarget.publicId('abc123'));
      expect(target!.slug, isNull);
    });

    test('an /s/ link resolves to its slug', () {
      final target = parseDeepLink(
        Uri.parse('https://$kDeepLinkHost/s/slopcafe-http-api'),
      );
      expect(target, const DeepLinkTarget.slug('slopcafe-http-api'));
      expect(target!.publicId, isNull);
    });

    test('http is claimed alongside https', () {
      expect(
        parseDeepLink(Uri.parse('http://$kDeepLinkHost/d/abc123')),
        const DeepLinkTarget.publicId('abc123'),
      );
    });

    test('the host comparison is case-insensitive', () {
      expect(
        parseDeepLink(Uri.parse('https://${kDeepLinkHost.toUpperCase()}/d/x')),
        const DeepLinkTarget.publicId('x'),
      );
    });

    // The byte paths a copied URL can carry still name the document, so they
    // open it rather than bouncing to a browser. The pinned-version case is a
    // deliberate under-delivery: it opens the latest view, because the Reader
    // owns version selection in its own state.
    test('trailing byte-path segments still name the document', () {
      expect(
        parseDeepLink(Uri.parse('https://$kDeepLinkHost/d/abc123/raw')),
        const DeepLinkTarget.publicId('abc123'),
      );
      expect(
        parseDeepLink(Uri.parse('https://$kDeepLinkHost/d/abc123/v/3/raw')),
        const DeepLinkTarget.publicId('abc123'),
      );
    });

    test('a trailing slash does not change the name', () {
      expect(
        parseDeepLink(Uri.parse('https://$kDeepLinkHost/s/some-slug/')),
        const DeepLinkTarget.slug('some-slug'),
      );
    });

    // A slug that travelled percent-encoded has to arrive as the name the
    // corpus actually stores, or the lookup asks for something that was never
    // written.
    test('the name is percent-decoded', () {
      expect(
        parseDeepLink(Uri.parse('https://$kDeepLinkHost/s/a%20b')),
        const DeepLinkTarget.slug('a b'),
      );
    });

    test('query strings and fragments are ignored', () {
      expect(
        parseDeepLink(Uri.parse('https://$kDeepLinkHost/s/x?utm=1#heading')),
        const DeepLinkTarget.slug('x'),
      );
    });
  });

  group('parseDeepLink — not ours', () {
    // Every one of these must return null rather than throw or half-match:
    // null is the "hand it back / do nothing" signal, and the caller treats it
    // as a no-op, not an error.
    test('another host is never claimed', () {
      expect(parseDeepLink(Uri.parse('https://example.com/d/abc123')), isNull);
    });

    test('a subdomain of the claimed host is not the claimed host', () {
      expect(
        parseDeepLink(Uri.parse('https://www.$kDeepLinkHost/d/abc123')),
        isNull,
      );
    });

    test('non-web schemes are rejected', () {
      expect(parseDeepLink(Uri.parse('ftp://$kDeepLinkHost/d/abc')), isNull);
      expect(parseDeepLink(Uri.parse('file:///d/abc')), isNull);
    });

    test('a path outside /d/ and /s/ is not a document', () {
      expect(parseDeepLink(Uri.parse('https://$kDeepLinkHost/')), isNull);
      expect(
        parseDeepLink(Uri.parse('https://$kDeepLinkHost/openapi.json')),
        isNull,
      );
      expect(parseDeepLink(Uri.parse('https://$kDeepLinkHost/admin/documents')), isNull);
    });

    test('an empty name is not a name', () {
      expect(parseDeepLink(Uri.parse('https://$kDeepLinkHost/d/')), isNull);
      expect(parseDeepLink(Uri.parse('https://$kDeepLinkHost/d')), isNull);
      expect(parseDeepLink(Uri.parse('https://$kDeepLinkHost/s//raw')), isNull);
      expect(parseDeepLink(Uri.parse('https://$kDeepLinkHost/s/%20')), isNull);
    });
  });

  group('DeepLinkTarget', () {
    // The two namespaces are not interchangeable — a slug and a public_id that
    // happen to read the same address different things — so value equality has
    // to keep them apart.
    test('a slug and a public_id with the same text are different targets', () {
      expect(
        const DeepLinkTarget.slug('x'),
        isNot(const DeepLinkTarget.publicId('x')),
      );
      expect(
        const DeepLinkTarget.slug('x').hashCode,
        isNot(const DeepLinkTarget.publicId('x').hashCode),
      );
    });
  });

  group('build configuration', () {
    // See the header: this is the invariant that makes the domain a
    // single-place change in practice rather than only on paper.
    test('the Gradle host matches kDeepLinkHost', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final match = RegExp(
        r'''manifestPlaceholders\["deepLinkHost"\]\s*=\s*"([^"]+)"''',
      ).firstMatch(gradle);

      expect(
        match,
        isNotNull,
        reason:
            'android/app/build.gradle.kts no longer declares a deepLinkHost '
            'manifest placeholder. The AndroidManifest intent-filter '
            'substitutes it, so without it the app claims no web links at all.',
      );
      expect(
        match!.group(1),
        kDeepLinkHost,
        reason:
            'The Gradle host and kDeepLinkHost disagree. Android would offer '
            'the app links for one domain while the parser only accepts the '
            'other, so every inbound link would open the app to nothing.',
      );
    });

    test('the manifest claims exactly /d/ and /s/ on the placeholder host', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(
        manifest,
        contains('android:autoVerify="true"'),
        reason:
            'Without autoVerify the App Links are unverified, so Android shows '
            'a disambiguation chooser (or just opens a browser) instead of the '
            'app.',
      );

      // Hosts are only ever the placeholder — a hard-coded domain here would
      // survive an adopter changing the Gradle value and silently keep
      // claiming ours.
      final hosts = RegExp(r'android:host="([^"]*)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toSet();
      expect(hosts, {r'${deepLinkHost}'});

      final prefixes = RegExp(r'android:pathPrefix="([^"]*)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toSet();
      expect(
        prefixes,
        {'/d/', '/s/'},
        reason:
            'The filter must stay narrow: claiming the whole origin would '
            'swallow the rendered site and every other page into an operator '
            'console that has nothing to show for them.',
      );
    });
  });
}
