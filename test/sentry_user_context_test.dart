import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A minimal `Authenticatable` model standing in for a host app's own user.
///
/// Hydrated through `setRawAttributes` (not `fill`) so a test can set `id`
/// without declaring it `fillable`, mirroring how a real model hydrates from
/// an API response rather than from a form.
class _TestUser extends Model with Authenticatable {
  _TestUser({required String id, String? email, String? teamId}) {
    setRawAttributes({
      'id': id,
      if (email != null) 'email': email,
      if (teamId != null) 'team_id': teamId,
    });
  }

  @override
  String get table => 'users';

  @override
  String get resource => 'users';

  @override
  String get id => getAttribute('id') as String? ?? '';

  String? get email => getAttribute('email') as String?;

  String? get teamId => getAttribute('team_id') as String?;
}

SentryUserContext<_TestUser> _context({
  Map<String, String> Function(_TestUser user)? extras,
}) {
  return SentryUserContext<_TestUser>(
    id: (user) => user.id,
    email: (user) => user.email,
    extras: extras,
  );
}

/// Reads the scope user Sentry currently holds, the only way to observe
/// [SentryUserContext.apply]'s effect without sending a real event.
Future<SentryUser?> _scopeUser() async {
  SentryUser? user;
  await Sentry.configureScope((scope) => user = scope.user);
  return user;
}

Future<Map<String, String>> _scopeTags() async {
  Map<String, String> tags = const {};
  await Sentry.configureScope((scope) => tags = scope.tags);
  return tags;
}

/// Locks what an issue reports about WHO hit it: an id, an email and
/// whatever [SentryUserContext]'s `extras` callback names. Nothing else.
///
/// The empty cases are the ones worth pinning: an `Authenticatable` whose id
/// extractor answers the empty string is treated as "no session", since
/// several magic-backed apps model a signed-out state as an empty model
/// rather than a null one.
void main() {
  group('userFor', () {
    test('it reports nobody when there is no session', () {
      expect(_context().userFor(null), isNull);
    });

    test('it reports nobody for a user with an empty id', () {
      expect(_context().userFor(_TestUser(id: '')), isNull);
    });

    test('it carries the id and the email', () {
      final reported = _context().userFor(
        _TestUser(id: 'usr_42', email: 'operator@example.test'),
      );

      expect(reported, isNotNull);
      expect(reported!.id, 'usr_42');
      expect(reported.email, 'operator@example.test');
    });

    test('it omits an email the user does not have', () {
      final reported = _context().userFor(_TestUser(id: 'usr_9'));

      expect(reported, isNotNull);
      expect(reported!.id, 'usr_9');
      expect(reported.email, isNull);
    });
  });

  group('install/apply against a live scope', () {
    setUp(() async {
      MagicApp.reset();
      Magic.flush();
      // A DSN is required to bind a real hub (`Sentry.isEnabled == false`
      // would leave `configureScope` a no-op), but nothing here sends an
      // event, so no request ever reaches it.
      await Sentry.init(
          (options) => options.dsn = 'https://public@o0.ingest.sentry.io/0');
    });

    tearDown(() async {
      Auth.unfake();
      await Sentry.close();
    });

    test('login sets the scope user id and email', () async {
      Auth.fake(user: _TestUser(id: 'usr_1', email: 'a@b.test'));

      _context().install();

      final reported = await _scopeUser();
      expect(reported, isNotNull);
      expect(reported!.id, 'usr_1');
      expect(reported.email, 'a@b.test');
    });

    test('logout clears the scope user', () async {
      Auth.fake(user: _TestUser(id: 'usr_1', email: 'a@b.test'));

      _context().install();
      await Auth.logout();

      expect(await _scopeUser(), isNull);
    });

    test('extras are tagged once a user is reported', () async {
      Auth.fake(user: _TestUser(id: 'usr_1', teamId: 'team_9'));

      _context(
        extras: (user) => user.teamId != null ? {'team_id': user.teamId!} : {},
      ).install();

      expect(await _scopeTags(), containsPair('team_id', 'team_9'));
    });

    test('extras are cleared on logout rather than left stale', () async {
      Auth.fake(user: _TestUser(id: 'usr_1', teamId: 'team_9'));

      _context(
        extras: (user) => user.teamId != null ? {'team_id': user.teamId!} : {},
      ).install();
      await Auth.logout();

      expect(await _scopeTags(), isNot(contains('team_id')));
    });

    test('installing twice applies once per bump, not twice', () async {
      // A second `install()` on the same instance used to add a second
      // listener with no removal of the first, so every future auth-state
      // bump ran `apply()` (and thus this `id` extractor) twice instead of
      // once. `id` is called on every `apply()` that sees a signed-in user
      // (`userFor` reads it unconditionally), which makes it a direct count
      // of how many times `apply()` actually ran for ONE bump.
      Auth.fake(user: _TestUser(id: 'usr_1'));

      int idCalls = 0;
      final context = SentryUserContext<_TestUser>(
        id: (user) {
          idCalls++;
          return user.id;
        },
        email: (user) => user.email,
      );

      context.install();
      context.install();
      idCalls = 0; // discard the two immediate applies `install()` itself ran

      // Bumped directly rather than through another `Auth.fake()` call: a
      // second fake swaps in a brand new notifier, which would prove nothing
      // about a listener registered on the notifier that already exists.
      Auth.stateNotifier.value++;

      expect(idCalls, 1);
    });
  });
}
