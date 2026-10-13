import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_network_interceptor.dart';

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
///    read from `MagicRouter.instance.routes` at scrub time, so a route added
///    after boot is covered too.
/// 3. OPAQUE API SEGMENTS. A breadcrumb or span URL is an API path, which the
///    app's routes do not describe. It is reduced with
///    [SentryNetworkInterceptor.normalizeEndpoint] (query dropped, numeric and
///    UUID segments become `{id}`), then any remaining segment of 32 or more
///    characters from `[A-Za-z0-9_-]` becomes `{token}`. The UUID exemption
///    comes from running after the reduction: a UUID is gone by then, while a
///    32-character hex string with no hyphens is exactly what a token looks
///    like and is masked.
///
/// Every hook MASKS and never drops: an event or breadcrumb the scrubber does
/// not recognise passes through unchanged. A numeric id and the `email` query
/// key are deliberately left alone; masking them would blind debugging for no
/// credential gained.
abstract final class SentryTokenScrubber {
  static const String _filtered = '[Filtered]';

  static const String _opaqueMask = '{token}';

  /// A `?key=value` or `&key=value` pair whose KEY names a secret.
  ///
  /// The value stops at `&`, `#` or whitespace so a url embedded in a
  /// breadcrumb message loses only the value, not the text after it.
  static final RegExp _sensitiveQueryPair = RegExp(
    r'([?&])([^=&#\s]*(?:token|password|secret|signature|credential|api_key)'
    r'[^=&#\s]*)=([^&#\s]*)',
    caseSensitive: false,
  );

  static final RegExp _opaqueSegment = RegExp(r'^[A-Za-z0-9_-]{32,}$');

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
  /// `request.fragment`, `transaction` and `contexts.trace`.
  static SentryEvent beforeSend(SentryEvent event, Hint hint) {
    _scrubEvent(event);

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
        span.data[entry.key] = _scrubValue(entry.key, entry.value, http: http);
      }
    }

    return transaction;
  }

  /// Masks [crumb] in place: its `message` and every string in its `data`.
  ///
  /// A null [crumb] stays null. An `http` breadcrumb (by `type` or `category`)
  /// also has its `url` reduced as an API path.
  static Breadcrumb? beforeBreadcrumb(Breadcrumb? crumb, Hint hint) {
    if (crumb == null) {
      return null;
    }

    final bool http = crumb.type == 'http' || crumb.category == 'http';
    final Map<String, dynamic>? data = crumb.data;

    crumb.message = _locationOrNull(crumb.message);

    if (data != null) {
      crumb.data = _scrubMap(data, http: http);
    }

    return crumb;
  }

  /// Reduces an API [url] to an endpoint that is safe to send and to group on.
  ///
  /// The query is dropped, numeric and UUID segments become `{id}`, a segment
  /// bound to a magic route token param is masked, and any other segment of 32
  /// or more `[A-Za-z0-9_-]` characters becomes `{token}`.
  static String scrubApiUrl(String url) {
    final String endpoint = SentryNetworkInterceptor.normalizeEndpoint(
      _scrubLocation(url),
    );

    return endpoint
        .split('/')
        .map((String segment) =>
            _opaqueSegment.hasMatch(segment) ? _opaqueMask : segment)
        .join('/');
  }

  static void _scrubEvent(SentryEvent event) {
    final SentryRequest? request = event.request;

    if (request != null) {
      request.url = _locationOrNull(request.url);
      request.queryString = _queryStringOrNull(request.queryString);
      request.fragment = _locationOrNull(request.fragment);
    }

    event.transaction = _locationOrNull(event.transaction);

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

  static Map<String, dynamic> _scrubMap(
    Map<String, dynamic> data, {
    required bool http,
  }) {
    return data.map(
      (String key, dynamic value) =>
          MapEntry(key, _scrubValue(key, value, http: http)),
    );
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

      return http && key == 'url' ? scrubApiUrl(value) : _scrubLocation(value);
    }

    if (value is Map<String, dynamic>) {
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
        scrubApiUrl(description.substring(urlStart));
  }

  static String? _locationOrNull(String? text) =>
      text == null ? null : _scrubLocation(text);

  static String? _queryStringOrNull(String? query) =>
      query == null ? null : _maskQueryString(query);

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
  /// text, after whitespace or right after `scheme://host`, so
  /// `/monitors/:token` never touches `/api/monitors/x`. The match is rebuilt
  /// segment by segment, which keeps the surrounding text and any trailing
  /// slash exactly as they were.
  static String _maskRouteTokens(String text) {
    String masked = text;

    for (final RouteDefinition route in MagicRouter.instance.routes) {
      final List<String> pattern = route.fullPath.split('/');
      final List<int> tokenSegments = <int>[
        for (int i = 0; i < pattern.length; i++)
          if (_isTokenParam(pattern[i])) i,
      ];

      if (tokenSegments.isEmpty) {
        continue;
      }

      final RegExp shape = RegExp(
        r'(?<=^|\s|://[^/\s]*)'
        '${pattern.map(_segmentShape).join('/')}'
        r'/?(?=$|[\s?#])',
      );

      masked = masked.replaceAllMapped(shape, (Match match) {
        final List<String> segments = match[0]!.split('/');

        for (final int index in tokenSegments) {
          segments[index] = _filtered;
        }

        return segments.join('/');
      });
    }

    return masked;
  }

  static bool _isTokenParam(String segment) =>
      segment.startsWith(':') && segment.toLowerCase().contains('token');

  static String _segmentShape(String segment) =>
      segment.startsWith(':') ? r'[^/\s?#]+' : RegExp.escape(segment);
}
