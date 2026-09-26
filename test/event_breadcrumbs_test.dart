import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// An event that opts into the breadcrumb trail.
class _DeeplinkOpened extends MagicEvent implements ReportsBreadcrumb {
  _DeeplinkOpened(this.path);

  final String path;

  @override
  String get breadcrumbCategory => 'deeplink.open';

  @override
  String get breadcrumbMessage => 'Deeplink opened';

  @override
  Map<String, Object?> get breadcrumbData => {'path': path};
}

/// A plain event, carrying no [ReportsBreadcrumb] contract.
class _PlainEvent extends MagicEvent {}

/// Locks what [EventBreadcrumbs.breadcrumbFor] reports and what it ignores.
///
/// Pure and testable with no Sentry hub, the same shape as
/// `SentryUserContext.userFor`: the mapping is asserted directly, without
/// ever sending a real breadcrumb.
void main() {
  group('EventBreadcrumbs.breadcrumbFor', () {
    test('maps a ReportsBreadcrumb event to its category, message and data',
        () {
      final Breadcrumb? crumb =
          EventBreadcrumbs.breadcrumbFor(_DeeplinkOpened('/monitors/42'));

      expect(crumb, isNotNull);
      expect(crumb!.category, 'deeplink.open');
      expect(crumb.message, 'Deeplink opened');
      expect(crumb.data, {'path': '/monitors/42'});
      expect(crumb.level, SentryLevel.info);
    });

    test('answers null for an event that does not implement ReportsBreadcrumb',
        () {
      expect(EventBreadcrumbs.breadcrumbFor(_PlainEvent()), isNull);
    });
  });
}
