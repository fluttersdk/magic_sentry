import 'package:flutter/foundation.dart' show listEquals;
import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_network_interceptor.dart';

/// A registered route with at least one `*token*` param: the pattern that
/// finds it in a text and the indexes of the segments to mask.
typedef _TokenRoute = ({RegExp shape, List<int> tokenSegments});

/// Masks URL-borne tokens in everything Sentry is about to send.
///
/// WHY THIS EXISTS. A magic route like `/invitations/:token/accept` puts a
/// credential in the PATH, and a reset link puts one in the QUERY. On web the
/// SDK copies `window.location` into `request.url` and the pathname into the
/// transaction name, and `sentry_dio` keeps the API path on every breadcrumb
/// and span, so a token reaches Sentry through half a dozen fields nobody
/// thinks of as sensitive.
///
/// THREE RULES, applied in this order:
///
/// 1. QUERY VALUES. A `?key=value` pair whose key contains `token`,
///    `password`, `secret`, `signature`, `credential` or `api_key` (any case)
///    keeps its key and loses its value.
/// 2. ROUTE-BOUND SEGMENTS. A path segment sitting where a registered magic
///    route has a param whose name contains `token` is masked. The routes are
///    read from `MagicRouter.instance.allRoutes` at scrub time, so a route
///    inside a layout group, or one added after boot, is covered too.
/// 3. OPAQUE API SEGMENTS. A breadcrumb or span URL is an API path, which the
///    app's routes do not describe, so any segment of 32 or more characters
///    from `[A-Za-z0-9_-]` becomes `{token}`. A UUID is exempt, since it is an
///    id and not a credential; a 32-character hex string with no hyphens is
///    exactly what a token looks like and is masked. Only the interceptor's
///    fingerprint, through [scrubApiUrl], also collapses ids to `{id}`.
///
/// Every hook MASKS and never drops: an event or breadcrumb the scrubber does
/// not recognise passes through unchanged. A numeric id and the `email` query
/// key are deliberately left alone; masking them would blind debugging for no
/// credential gained.
///
/// FAIL CLOSED. The SDK catches a throwing `beforeSend` and sends the event it
/// was given, half scrubbed. So a hook that fails here replaces every field it
/// would have scrubbed with `[Filtered]` and still returns the event.
abstract final class SentryTokenScrubber {
  static const String _filtered = '[Filtered]';

  static const String _opaqueMask = '{token}';

  /// A `?key=value`, `&key=value` or `#key=value` pair whose KEY names a secret.
  ///
  /// `#` covers a fragment that opens with a pair, the OAuth implicit-flow
  /// `#access_token=...` shape. The value stops at `&`, `#` or whitespace so a
  /// url embedded in a breadcrumb message loses only the value, not the text
  /// after it.
  static final RegExp _sensitiveQueryPair = RegExp(
    r'([?&#])([^=&#\s]*(?:token|password|secret|signature|credential|api_key)'
    r'[^=&#\s]*)=([^&#\s]*)',
    caseSensitive: false,
  );

  /// A path segment of 32 or more token characters, with the slash that
  /// introduces it kept in a group so no lookbehind is needed (Safari before
  /// 16.4 throws a SyntaxError on one, and this runs in the web client).
  static final RegExp _opaquePathSegment = RegExp(
    r'(/)([A-Za-z0-9_-]{32,})(?=$|[/?#&\s])',
  );

  static List<String> _compiledPaths = <String>[];

  static List<_TokenRoute> _compiledRoutes = <_TokenRoute>[];

  /// Puts the scrubber in front of every hook the app has already set.
  ///
  /// Call it AFTER the app's own `configure`: an app hook assigned later would
  /// replace the scrubber instead of running behind it. Each wrapped hook
  /// scrubs first and hands the scrubbed value to the app's hook, so an app
  /// hook that drops or rewrites still has the last word on what is sent but
  /// can never see a raw token.
  static void install(SentryOptions options) {
    final BeforeSendCallback? appBeforeSend = options.beforeSend;
    final BeforeSendTransactionCallback? appBeforeSendTransaction =
        options.beforeSendTransaction;
    final BeforeBreadcrumbCallback? appBeforeBreadcrumb =
        options.beforeBreadcrumb;

    options.beforeSend = (SentryEvent event, Hint hint) {
      final SentryEvent scrubbed = beforeSend(event, hint);

      return appBeforeSend == null ? scrubbed : appBeforeSend(scrubbed, hint);
    };

    options.beforeSendTransaction = (SentryTransaction transaction, Hint hint) {
      final SentryTransaction scrubbed = beforeSendTransaction(
        transaction,
        hint,
      );

      return appBeforeSendTransaction == null
          ? scrubbed
          : appBeforeSendTransaction(scrubbed, hint);
    };

    options.beforeBreadcrumb = (Breadcrumb? crumb, Hint hint) {
      final Breadcrumb? scrubbed = beforeBreadcrumb(crumb, hint);

      return appBeforeBreadcrumb == null
          ? scrubbed
          : appBeforeBreadcrumb(scrubbed, hint);
    };
  }

  /// Masks [event] in place: `request.url`, `request.queryString`,
  /// `request.fragment`, `transaction`, `contexts.trace`, every exception
  /// `value` and the message, since an error text can embed the current URI.
  ///
  /// Fails closed: if scrubbing throws, those fields are replaced wholesale.
  static SentryEvent beforeSend(SentryEvent event, Hint hint) {
    try {
      _scrubEvent(event);
    } on Object {
      _maskEvent(event);
    }

    return event;
  }

  /// Masks [transaction] in place: everything [beforeSend] covers, plus every
  /// span's description and data.
  ///
  /// Legacy spans are scrubbed here and not in `beforeSendSpan`, which only
  /// sees the V2 streaming spans.
  static SentryTransaction beforeSendTransaction(
    SentryTransaction transaction,
    Hint hint,
  ) {
    try {
      _scrubEvent(transaction);

      for (final SentrySpan span in transaction.spans) {
        final bool http = span.context.operation.startsWith('http');
        final String? description = span.context.description;

        if (description != null) {
          span.context.description = http
              ? _scrubHttpDescription(description)
              : _scrubLocation(description);
        }

        // Written through the map, not `setData`: a finished span, which every
        // span in a sent transaction is, ignores `setData`.
        for (final MapEntry<String, dynamic> entry
            in span.data.entries.toList()) {
          span.data[entry.key] =
              _scrubValue(entry.key, entry.value, http: http);
        }
      }
    } on Object {
      _maskEvent(transaction);

      for (final SentrySpan span in transaction.spans) {
        span.context.description = _maskedIfSet(span.context.description);
        span.data.updateAll((String key, dynamic value) => _maskValue(value));
      }
    }

    return transaction;
  }

  /// Masks [crumb] in place: its `message` and every string in its `data`.
  ///
  /// A null [crumb] stays null. An `http` breadcrumb (by `type` or `category`)
  /// also has its `url` checked for an opaque path segment. Fails closed: if
  /// scrubbing throws, the message and every string in `data` are replaced.
  static Breadcrumb? beforeBreadcrumb(Breadcrumb? crumb, Hint hint) {
    if (crumb == null) {
      return null;
    }

    try {
      final bool http = crumb.type == 'http' || crumb.category == 'http';
      final Map<String, dynamic>? data = crumb.data;

      crumb.message = _locationOrNull(crumb.message);

      if (data != null) {
        crumb.data = _scrubMap(data, http: http);
      }
    } on Object {
      crumb.message = _maskedIfSet(crumb.message);
      crumb.data = crumb.data?.map(
        (String key, dynamic value) => MapEntry(key, _maskValue(value)),
      );
    }

    return crumb;
  }

  /// Reduces an API [url] to an endpoint that is safe to group on.
  ///
  /// The query is dropped, numeric and UUID segments become `{id}`, a segment
  /// bound to a magic route token param is masked, and any other segment of 32
  /// or more `[A-Za-z0-9_-]` characters becomes `{token}`. Meant for the
  /// interceptor's fingerprint and endpoint; a breadcrumb or span url keeps its
  /// ids and query, and is only masked.
  static String scrubApiUrl(String url) {
    return _maskOpaqueSegments(
      SentryNetworkInterceptor.normalizeEndpoint(_scrubLocation(url)),
    );
  }

  static void _scrubEvent(SentryEvent event) {
    final SentryRequest? request = event.request;

    if (request != null) {
      request.url = _locationOrNull(request.url);
      request.queryString = _queryStringOrNull(request.queryString);
      request.fragment = _fragmentOrNull(request.fragment);
    }

    event.transaction = _locationOrNull(event.transaction);

    // An error message routinely embeds the URI the app was on.
    for (final SentryException exception in event.exceptions ?? const []) {
      exception.value = _locationOrNull(exception.value);
    }

    final SentryMessage? message = event.message;

    if (message != null) {
      message.formatted = _scrubLocation(message.formatted);
      message.template = _locationOrNull(message.template);
    }

    final SentryTraceContext? trace = event.contexts.trace;

    if (trace != null) {
      trace.description = _locationOrNull(trace.description);

      final Map<String, dynamic>? data = trace.data;

      // Assigned, not mutated: the transaction hands over the tracer's
      // unmodifiable view of its data.
      if (data != null) {
        trace.data = _scrubMap(data, http: false);
      }
    }
  }

  /// Replaces what [_scrubEvent] would have scrubbed, without reading any of
  /// it back through the scrubber that just failed.
  static void _maskEvent(SentryEvent event) {
    final SentryRequest? request = event.request;

    if (request != null) {
      request.url = _maskedIfSet(request.url);
      request.queryString = _maskedIfSet(request.queryString);
      request.fragment = _maskedIfSet(request.fragment);
    }

    event.transaction = _maskedIfSet(event.transaction);

    for (final SentryException exception in event.exceptions ?? const []) {
      exception.value = _maskedIfSet(exception.value);
    }

    final SentryMessage? message = event.message;

    if (message != null) {
      message.formatted = _filtered;
      message.template = _maskedIfSet(message.template);
    }

    final SentryTraceContext? trace = event.contexts.trace;

    if (trace != null) {
      trace.description = _maskedIfSet(trace.description);
      trace.data = trace.data?.map(
        (String key, dynamic value) => MapEntry(key, _maskValue(value)),
      );
    }
  }

  static String? _maskedIfSet(String? text) => text == null ? null : _filtered;

  /// Numbers and booleans carry no URL, so they survive a fail-closed mask.
  static dynamic _maskValue(dynamic value) =>
      value is num || value is bool ? value : _filtered;

  static Map<String, dynamic> _scrubMap(
    Map<dynamic, dynamic> data, {
    required bool http,
  }) {
    return <String, dynamic>{
      for (final MapEntry<dynamic, dynamic> entry in data.entries)
        '${entry.key}': _scrubValue('${entry.key}', entry.value, http: http),
    };
  }

  static dynamic _scrubValue(
    String key,
    dynamic value, {
    required bool http,
  }) {
    if (value is String) {
      if (key == 'http.query') {
        return _maskQueryString(value);
      }

      return http && key == 'url'
          ? _scrubHttpUrl(value)
          : _scrubLocation(value);
    }

    if (value is Map) {
      return _scrubMap(value, http: http);
    }

    if (value is List<dynamic>) {
      return value
          .map((dynamic item) => _scrubValue(key, item, http: http))
          .toList();
    }

    return value;
  }

  /// A `sentry_dio` span description is `METHOD url`; only the url is reduced.
  static String _scrubHttpDescription(String description) {
    final int urlStart = description.lastIndexOf(' ') + 1;

    return description.substring(0, urlStart) +
        _scrubHttpUrl(description.substring(urlStart));
  }

  /// A breadcrumb or span url keeps its ids and its query: only a sensitive
  /// query value, a route-bound token and an opaque segment are masked.
  static String _scrubHttpUrl(String url) =>
      _maskOpaqueSegments(_scrubLocation(url));

  static String _maskOpaqueSegments(String text) {
    return text.replaceAllMapped(_opaquePathSegment, (Match match) {
      // A UUID is an id, not a credential. `normalizeEndpoint` already knows
      // the shape, so it is asked rather than restated.
      return SentryNetworkInterceptor.normalizeEndpoint(match[2]!) == '{id}'
          ? match[0]!
          : '${match[1]}$_opaqueMask';
    });
  }

  static String? _locationOrNull(String? text) =>
      text == null ? null : _scrubLocation(text);

  static String? _queryStringOrNull(String? query) =>
      query == null ? null : _maskQueryString(query);

  /// A fragment arrives without its `#`, so a pair at its start has nothing to
  /// anchor on; the `#` is put back for the pair pass, then the route pass runs
  /// over the bare fragment, where a hash-routed path starts.
  static String? _fragmentOrNull(String? fragment) => fragment == null
      ? null
      : _maskRouteTokens(_maskQueryValues('#$fragment').substring(1));

  static String _scrubLocation(String text) =>
      _maskRouteTokens(_maskQueryValues(text));

  static String _maskQueryValues(String text) {
    return text.replaceAllMapped(
      _sensitiveQueryPair,
      (Match match) => '${match[1]}${match[2]}=$_filtered',
    );
  }

  /// A bare query string has no leading `?` for the pair pattern to anchor on.
  static String _maskQueryString(String query) =>
      _maskQueryValues('?$query').substring(1);

  /// Masks the segment of every registered route param named `*token*`.
  ///
  /// A route matches only as a whole path, starting at the beginning of the
  /// text, after whitespace or right after `scheme://host` (or `scheme://host/#`
  /// for a hash-routed url), so `/monitors/:token` never touches
  /// `/api/monitors/x`. The match is rebuilt segment by segment, which keeps the
  /// surrounding text and any trailing slash exactly as they were.
  static String _maskRouteTokens(String text) {
    String masked = text;

    for (final _TokenRoute route in _tokenRoutes()) {
      masked = masked.replaceAllMapped(route.shape, (Match match) {
        final List<String> segments = match[2]!.split('/');

        for (final int index in route.tokenSegments) {
          segments[index] = _filtered;
        }

        return '${match[1]}${segments.join('/')}';
      });
    }

    return masked;
  }

  /// The compiled token routes, rebuilt only when the registered paths change.
  ///
  /// Compared by path and not by count: a route replaced by another, or the
  /// router reset and re-registered, keeps the same count.
  static List<_TokenRoute> _tokenRoutes() {
    // `allRoutes`, not `routes`: the latter holds only top-level routes, and
    // magic_starter keeps `/invitations/:token/accept` inside a layout group.
    final List<String> paths = <String>[
      for (final RouteDefinition route in MagicRouter.instance.allRoutes)
        route.fullPath,
    ];

    if (listEquals(paths, _compiledPaths)) {
      return _compiledRoutes;
    }

    _compiledPaths = paths;
    _compiledRoutes = <_TokenRoute>[
      for (final String path in paths)
        if (path.split('/').any(_isTokenParam)) _compileRoute(path),
    ];

    return _compiledRoutes;
  }

  static _TokenRoute _compileRoute(String path) {
    final List<String> pattern = path.split('/');

    return (
      shape: RegExp(
        r'(^|\s|://[^/\s]*(?:/#)?)'
        '(${pattern.map(_segmentShape).join('/')}'
        r'/?)(?=$|[\s?#])',
      ),
      tokenSegments: <int>[
        for (int i = 0; i < pattern.length; i++)
          if (_isTokenParam(pattern[i])) i,
      ],
    );
  }

  static bool _isTokenParam(String segment) =>
      segment.startsWith(':') && segment.toLowerCase().contains('token');

  static String _segmentShape(String segment) =>
      segment.startsWith(':') ? r'[^/\s?#]+' : RegExp.escape(segment);
}
