import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Keeps Sentry's scope user in step with `Auth.stateNotifier`.
///
/// The host app supplies [id] and [email] extractors for its own user model
/// [T], plus an optional [extras] callback for anything else worth tagging on
/// every event (a team id, a plan, whatever the app's own domain needs).
/// This package has no opinion on what [T] is or what belongs in [extras];
/// it only owns the WHEN.
///
/// ## Kept in sync by the auth state, not by each call site
///
/// [install] subscribes to `Auth.stateNotifier`, which fires on login, on
/// logout, on a session restore at boot and (in an app with teams) on a team
/// switch. Doing it there rather than at each of those call sites is what
/// keeps a future one correct for free, and it is also what guarantees the
/// LOGOUT case: a scope that keeps the previous user attached would file the
/// next visitor's errors under the person who signed out, which is worse
/// than having no user at all.
class SentryUserContext<T extends Model> {
  /// Creates a context that reads [T] through [id] and [email].
  ///
  /// [id] and [email] should read straight off the model (no network calls,
  /// no side effects): they run on every auth state change. [extras] is
  /// called only when a user is reported, and its keys REPLACE whatever the
  /// previous call set, so the same key can carry a new value across a team
  /// switch without leaking the old one.
  SentryUserContext({
    required String Function(T user) id,
    required String? Function(T user) email,
    Map<String, String> Function(T user)? extras,
  })  : _id = id,
        _email = email,
        _extras = extras;

  /// Extracts the reported user id from [T]. Empty means "no user".
  final String Function(T user) _id;

  /// Extracts the reported email from [T], or null when the account has none
  /// (a guest account, typically).
  final String? Function(T user) _email;

  /// Extracts extra scope tags from [T], applied only when a user is
  /// reported.
  final Map<String, String> Function(T user)? _extras;

  /// The tag keys the last [apply] set, so the next call can clear exactly
  /// those rather than guessing at what [_extras] might have named.
  Set<String> _extraTagKeys = <String>{};

  /// The notifier [install] last subscribed [apply] to, or null before the
  /// first call.
  ///
  /// Identity-compared rather than a boolean latch: `Auth.stateNotifier`
  /// itself can change across an app's lifetime (a test that fakes a new
  /// guard between installs, for instance), so a plain "already installed"
  /// flag would refuse to resubscribe to a genuinely new notifier and this
  /// would silently stop following auth state instead of double-subscribing.
  ValueNotifier<int>? _installedOn;

  /// Start following the auth state, and apply whatever it says right now.
  ///
  /// The immediate call matters: `Auth.restore()` typically runs during boot,
  /// so by the time this is installed there is often already a signed-in
  /// user, and waiting for the next change would leave the whole first
  /// session anonymous.
  ///
  /// Safe to call more than once on the same instance: a repeat is a no-op
  /// past the immediate [apply] (still run, since it only reasserts the
  /// current state) rather than a second subscription. Without the guard, a
  /// second `install()` on an unchanged notifier would leave [apply] running
  /// TWICE per future auth-state bump, once for each subscription.
  void install() {
    apply();

    final ValueNotifier<int> notifier = Auth.stateNotifier;

    if (identical(_installedOn, notifier)) {
      return;
    }

    _installedOn?.removeListener(apply);
    _installedOn = notifier..addListener(apply);
  }

  /// Push the current auth state into Sentry's scope.
  ///
  /// A no-op in practice when the SDK has no DSN, which is every debug run.
  void apply() {
    final bool signedIn = Auth.check();
    final T? user = signedIn ? Auth.user<T>() : null;
    final SentryUser? reported = userFor(user);

    Sentry.configureScope((scope) {
      // Explicitly null on sign-out. See the class docblock: a stale user is
      // worse than none.
      scope.setUser(reported);

      for (final String key in _extraTagKeys) {
        scope.removeTag(key);
      }
      _extraTagKeys = <String>{};

      if (reported == null || user == null || _extras == null) {
        return;
      }

      final Map<String, String> extras = _extras(user);

      extras.forEach(scope.setTag);
      _extraTagKeys = extras.keys.toSet();
    });
  }

  /// The Sentry user for [user], or null when there is nobody to report.
  ///
  /// Null for an ABSENT user and equally for one whose [_id] answers the
  /// empty string, since several magic-backed apps model "no session" as an
  /// empty user object rather than a null one.
  @visibleForTesting
  SentryUser? userFor(T? user) {
    if (user == null) {
      return null;
    }

    final String id = _id(user);

    if (id.isEmpty) {
      return null;
    }

    final String? email = _email(user);

    return SentryUser(
      id: id,
      email: (email != null && email.isNotEmpty) ? email : null,
    );
  }
}
