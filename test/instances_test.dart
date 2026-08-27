// Unit tests for switching between Slopcafe instances.
//
// The feature reads as a convenience — stop retyping an operator token — but the
// thing that makes it safe is an isolation property, and that property is
// invisible from any single screen:
//
//   - EVERY INSTANCE OWNS ITS OWN DERIVED STATE. `public_id` is a per-deployment
//     fact, so two instances can mint the same id for different documents. The
//     offline cache is namespaced by `SlopcafeInstance.id` to keep those apart
//     (`document_cache.dart`), which makes id minting a correctness concern
//     rather than a cosmetic one: two deployments must never share an id, and
//     one deployment must keep its id across a rename.
//   - THE APP IS NEVER POINTED AT NOTHING. `activeId` either names a member of
//     the set or is null because the set is empty. Every mutator has to preserve
//     that, including the one that removes the instance currently in use — a set
//     that survives a remove with a dangling pointer reads as "unconfigured" and
//     bounces the operator to first-run setup with their instances still saved.
//   - A SAVED SET SURVIVES A BAD RECORD. The set is one secure-storage entry, so
//     a single unparseable instance must not take the others down with it; the
//     failure mode would be an operator locked out of every deployment at once.
//
// Hermetic: `instances.dart` is a pure module — value types and functions over
// them, no Flutter, no `dart:io`, no keychain. Everything below is exercised
// directly, the same way `review.dart` and `links.dart` are.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/instances.dart';

SlopcafeInstance _instance({
  required String id,
  String? label,
  String baseUrl = 'https://slopcafe.com',
  String token = 'op-token',
  List<String> clientIds = const [],
}) => SlopcafeInstance(
  id: id,
  label: label ?? id,
  baseUrl: baseUrl,
  operatorToken: token,
  unboundOAuthClientIds: clientIds,
);

void main() {
  group('normalizeBaseUrl', () {
    test('trims whitespace and every trailing slash', () {
      expect(
        normalizeBaseUrl('  https://slopcafe.com/  '),
        'https://slopcafe.com',
      );
      expect(
        normalizeBaseUrl('https://slopcafe.com///'),
        'https://slopcafe.com',
      );
    });

    test(
      'leaves a path-bearing deployment alone apart from the trailing slash',
      () {
        expect(
          normalizeBaseUrl('https://host.dev/api/'),
          'https://host.dev/api',
        );
      },
    );
  });

  group('newInstanceId', () {
    // The id is used verbatim as a cache directory name, so anything that is
    // not [a-z0-9-] would have to be sanitised somewhere else instead.
    test('is a filesystem-safe slug of the host', () {
      expect(
        newInstanceId('https://slopcafe.com', taken: const []),
        'slopcafe-com',
      );
      expect(
        newInstanceId('https://Fork.Slopcafe.Dev', taken: const []),
        'fork-slopcafe-dev',
      );
    });

    test('keeps the port, so two deployments on one host stay distinct', () {
      expect(
        newInstanceId('http://localhost:8787', taken: const []),
        'localhost-8787',
      );
      expect(
        newInstanceId('http://localhost:8788', taken: const []),
        'localhost-8788',
      );
    });

    // The same host saved twice under two different operator tokens really is
    // two instances, and they must not land on one cache namespace.
    test('suffixes rather than merges when the slug is already taken', () {
      expect(
        newInstanceId('https://slopcafe.com', taken: const ['slopcafe-com']),
        'slopcafe-com-2',
      );
      expect(
        newInstanceId(
          'https://slopcafe.com',
          taken: const ['slopcafe-com', 'slopcafe-com-2'],
        ),
        'slopcafe-com-3',
      );
    });

    test('a URL with no readable host still yields a usable id', () {
      expect(newInstanceId('not a url', taken: const []), 'instance');
      expect(
        newInstanceId('not a url', taken: const ['instance']),
        'instance-2',
      );
    });
  });

  group('defaultLabelFor', () {
    test('names an instance after its host', () {
      expect(defaultLabelFor('https://slopcafe.com/'), 'slopcafe.com');
    });

    test('drops a www. prefix, which never distinguishes two deployments', () {
      expect(defaultLabelFor('https://www.slopcafe.com'), 'slopcafe.com');
    });

    test('falls back to the raw URL rather than an empty row', () {
      expect(defaultLabelFor('gibberish'), 'gibberish');
    });
  });

  group('InstanceSet — the active pointer', () {
    test('an empty set is unconfigured and has no active instance', () {
      const set = InstanceSet.empty();
      expect(set.isEmpty, isTrue);
      expect(set.active, isNull);
      expect(set.isConfigured, isFalse);
    });

    test('the first instance added becomes active', () {
      final set = const InstanceSet.empty().upsert(_instance(id: 'a'));
      expect(set.activeId, 'a');
      expect(set.isConfigured, isTrue);
    });

    // Adding a deployment is how an operator stands a new one up, so landing on
    // it is the useful default — and it is what makes "add, then immediately
    // test against it" work without a second tap.
    test('a later instance added also becomes active', () {
      final set = const InstanceSet.empty()
          .upsert(_instance(id: 'a'))
          .upsert(_instance(id: 'b'));
      expect(set.activeId, 'b');
    });

    // Editing a background instance from Settings must not yank the app onto it
    // mid-task.
    test('updating an existing instance does not steal focus', () {
      final set = const InstanceSet.empty()
          .upsert(_instance(id: 'a'))
          .upsert(_instance(id: 'b'))
          .activate('a')
          .upsert(_instance(id: 'b', label: 'renamed'));
      expect(set.activeId, 'a');
      expect(set.byId('b')!.label, 'renamed');
      expect(set.instances, hasLength(2));
    });

    test('an update replaces in place rather than appending', () {
      final set = const InstanceSet.empty()
          .upsert(_instance(id: 'a', label: 'first'))
          .upsert(_instance(id: 'a', label: 'second'));
      expect(set.instances, hasLength(1));
      expect(set.instances.single.label, 'second');
    });

    test('activate ignores an id that names nothing', () {
      final set = const InstanceSet.empty().upsert(_instance(id: 'a'));
      expect(set.activate('nope').activeId, 'a');
    });
  });

  group('InstanceSet — removal keeps the pointer valid', () {
    test(
      'removing the active instance falls through to one still standing',
      () {
        final set = const InstanceSet.empty()
            .upsert(_instance(id: 'a'))
            .upsert(_instance(id: 'b'))
            .remove('b');
        expect(set.activeId, 'a');
        expect(set.isConfigured, isTrue);
      },
    );

    test('removing a background instance leaves the active one alone', () {
      final set = const InstanceSet.empty()
          .upsert(_instance(id: 'a'))
          .upsert(_instance(id: 'b'))
          .remove('a');
      expect(set.activeId, 'b');
    });

    test('removing the last instance empties the set rather than dangling', () {
      final set = const InstanceSet.empty()
          .upsert(_instance(id: 'a'))
          .remove('a');
      expect(set.isEmpty, isTrue);
      expect(set.activeId, isNull);
      expect(set.isConfigured, isFalse);
    });
  });

  group('InstanceSet.byHost — inbound link routing', () {
    final set = const InstanceSet.empty()
        .upsert(_instance(id: 'up', baseUrl: 'https://slopcafe.com'))
        .upsert(_instance(id: 'fork', baseUrl: 'https://fork.slopcafe.dev'));

    test('finds the instance serving a host regardless of which is active', () {
      expect(set.activeId, 'fork');
      expect(set.byHost('slopcafe.com')!.id, 'up');
    });

    test('the comparison is case-insensitive and ignores whitespace', () {
      expect(set.byHost('  SlopCafe.COM ')!.id, 'up');
    });

    test('a host nothing serves resolves to nothing', () {
      expect(set.byHost('example.com'), isNull);
      expect(set.byHost(''), isNull);
    });

    test('same-host/different-port instances collapse to the first match', () {
      // Uri.host omits the port, so same-host/different-port instances share a
      // host key. The pair is still distinct by id — which is what the cache
      // namespace keys on — but link routing cannot tell them apart, and this
      // pins that the first match is what it returns rather than a crash.
      final local = const InstanceSet.empty()
          .upsert(_instance(id: 'a', baseUrl: 'http://localhost:8787'))
          .upsert(_instance(id: 'b', baseUrl: 'http://localhost:8788'));
      expect(local.byHost('localhost')!.id, 'a');
    });
  });

  group('JSON round-trip', () {
    test('a set survives encode/decode intact', () {
      final original = const InstanceSet.empty()
          .upsert(
            _instance(
              id: 'up',
              label: 'Production',
              baseUrl: 'https://slopcafe.com',
              token: 'token-a',
              clientIds: ['client-1', 'client-2'],
            ),
          )
          .upsert(
            _instance(
              id: 'fork',
              label: 'Fork',
              baseUrl: 'https://fork.slopcafe.dev',
              token: 'token-b',
            ),
          )
          .activate('up');

      final restored = InstanceSet.fromJson(
        json.decode(json.encode(original.toJson())),
      );
      expect(restored, original);
      expect(restored.activeId, 'up');
      expect(restored.active!.operatorToken, 'token-a');
      expect(restored.active!.unboundOAuthClientIds, ['client-1', 'client-2']);
    });

    // One bad record must not lock the operator out of every deployment.
    test('an unparseable instance is dropped, the rest survive', () {
      final restored = InstanceSet.fromJson({
        'active_id': 'good',
        'instances': [
          {
            'id': 'good',
            'base_url': 'https://slopcafe.com',
            'operator_token': 't',
          },
          {'id': 'no-url', 'operator_token': 't'},
          {'base_url': 'https://x.dev', 'operator_token': 't'},
          'not even a map',
        ],
      });
      expect(restored.instances, hasLength(1));
      expect(restored.activeId, 'good');
    });

    test('a duplicate id keeps the first record rather than shadowing it', () {
      final restored = InstanceSet.fromJson({
        'instances': [
          {
            'id': 'a',
            'label': 'first',
            'base_url': 'https://a.dev',
            'operator_token': 't',
          },
          {
            'id': 'a',
            'label': 'second',
            'base_url': 'https://b.dev',
            'operator_token': 't',
          },
        ],
      });
      expect(restored.instances, hasLength(1));
      expect(restored.instances.single.label, 'first');
    });

    test('a record with no label is named after its host', () {
      final restored = InstanceSet.fromJson({
        'instances': [
          {
            'id': 'a',
            'base_url': 'https://fork.slopcafe.dev',
            'operator_token': 't',
          },
        ],
      });
      expect(restored.instances.single.label, 'fork.slopcafe.dev');
    });

    // Garbage in storage routes to first-run setup, not to a crash on launch.
    test('a malformed set reads as empty', () {
      expect(InstanceSet.fromJson(null), const InstanceSet.empty());
      expect(InstanceSet.fromJson('nonsense'), const InstanceSet.empty());
      expect(
        InstanceSet.fromJson({'instances': 'not a list'}),
        const InstanceSet.empty(),
      );
    });

    // The pointer is persisted separately from the members, so a set written by
    // a build that resolved it differently must still come back consistent.
    test('an active_id naming nothing falls back to the first member', () {
      final restored = InstanceSet.fromJson({
        'active_id': 'ghost',
        'instances': [
          {'id': 'a', 'base_url': 'https://a.dev', 'operator_token': 't'},
        ],
      });
      expect(restored.activeId, 'a');
      expect(restored.isConfigured, isTrue);
    });
  });

  group('the isolation property', () {
    // The one thing that keeps two deployments' documents from being served
    // under each other's names. See the header note.
    test('two saved deployments never share a cache namespace', () {
      var set = const InstanceSet.empty();
      for (final url in const [
        'https://slopcafe.com',
        'https://fork.slopcafe.dev',
        'http://localhost:8787',
        'https://slopcafe.com', // the same host, a second operator token
      ]) {
        set = set.upsert(
          SlopcafeInstance(
            id: newInstanceId(url, taken: set.instances.map((i) => i.id)),
            label: defaultLabelFor(url),
            baseUrl: url,
            operatorToken: 't',
          ),
        );
      }
      final ids = set.instances.map((i) => i.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('renaming an instance keeps its id, and so its cached documents', () {
      final before = const InstanceSet.empty().upsert(
        _instance(id: 'slopcafe-com', label: 'slopcafe.com'),
      );
      final after = before.upsert(
        before.byId('slopcafe-com')!.copyWith(label: 'Production'),
      );
      expect(after.instances.single.id, 'slopcafe-com');
      expect(after.instances.single.label, 'Production');
    });

    test('an instance carries its own unbound OAuth client ids', () {
      final set = const InstanceSet.empty()
          .upsert(_instance(id: 'a', clientIds: ['client-a']))
          .upsert(_instance(id: 'b', clientIds: ['client-b']));
      expect(set.byId('a')!.unboundOAuthClientIds, ['client-a']);
      expect(set.byId('b')!.unboundOAuthClientIds, ['client-b']);
    });
  });
}
