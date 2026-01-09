import 'package:dio/dio.dart';

import '../calendar/calendar.dart';
import '../client/dio_webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../webdav/multistatus.dart';
import '../webdav/xml_namespaces.dart';
import 'event.dart';
import 'icalendar_parser.dart';

/// Service for event CRUD operations
class EventService {
  final DioWebDavClient _client;

  EventService(this._client);

  /// List events in a calendar
  ///
  /// Uses calendar-query with time-range filter for server-side filtering.
  /// If server doesn't return calendar-data (like Naver), uses the filtered
  /// URLs with calendar-multiget to fetch actual event data.
  ///
  /// [calendar] Target calendar
  /// [start] Filter start date (optional, UTC)
  /// [end] Filter end date (optional, UTC)
  Future<List<CalendarEvent>> list(
    Calendar calendar, {
    DateTime? start,
    DateTime? end,
  }) async {
    final body = _buildCalendarQueryBody(start: start, end: end);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return [];

      final events = <CalendarEvent>[];
      final urlsWithoutData = <String>[];

      // Parse responses - collect events or URLs
      for (final davResponse in multiStatus.responses) {
        final calendarData = davResponse.getProperty(
          'calendar-data',
          namespace: XmlNamespaces.caldav,
        );

        if (calendarData != null && calendarData.isNotEmpty) {
          // Server returned calendar-data (standard behavior)
          final etag = davResponse.getProperty(
            'getetag',
            namespace: XmlNamespaces.dav,
          );
          final event = ICalendarParser.parseEvent(
            calendarData,
            calendarId: calendar.uid,
            href: calendar.href.resolve(davResponse.href),
            etag: etag,
            isReadOnly: calendar.isReadOnly,
          );
          if (event != null) events.add(event);
        } else if (davResponse.href.endsWith('.ics')) {
          // No calendar-data but has URL (Naver-style)
          urlsWithoutData.add(davResponse.href);
        }
      }

      // If we got events directly, return them
      if (events.isNotEmpty) return events;

      // No calendar-data returned - fetch via multiget (URLs are already filtered!)
      if (urlsWithoutData.isNotEmpty) {
        return _fetchWithMultiget(calendar, urlsWithoutData);
      }

      return [];
    } on DioException catch (e) {
      throw CalDavException(
        'Failed to list events: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Batch fetch events using calendar-multiget
  Future<List<CalendarEvent>> _fetchWithMultiget(
    Calendar calendar,
    List<String> eventPaths,
  ) async {
    if (eventPaths.isEmpty) return [];

    // Build href elements for multiget
    final hrefs = eventPaths.map((p) => '<D:href>$p</D:href>').join('\n');

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  $hrefs
</C:calendar-multiget>''';

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final events = <CalendarEvent>[];

      for (final davResponse in multiStatus.responses) {
        final calendarData = davResponse.getProperty(
          'calendar-data',
          namespace: XmlNamespaces.caldav,
        );

        if (calendarData == null || calendarData.isEmpty) continue;

        final etag = davResponse.getProperty(
          'getetag',
          namespace: XmlNamespaces.dav,
        );

        final event = ICalendarParser.parseEvent(
          calendarData,
          calendarId: calendar.uid,
          href: calendar.href.resolve(davResponse.href),
          etag: etag,
          isReadOnly: calendar.isReadOnly,
        );

        if (event != null) events.add(event);
      }

      return events;
    } on DioException catch (e) {
      throw CalDavException(
        'Failed to fetch events: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Create a new event
  ///
  /// Returns the created event with href and etag
  Future<CalendarEvent> create(Calendar calendar, CalendarEvent event) async {
    final eventPath = calendar.href.resolve('${event.uid}.ics');

    try {
      final response = await _client.put(
        eventPath.toString(),
        body: event.toIcalendar(),
        ifNoneMatch: '*', // Only create if not exists
      );

      final etag = response.headers.value('etag');

      return event.copyWith(
        href: eventPath,
        etag: etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException('Event already exists');
      }
      throw CalDavException(
        'Failed to create event: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Update an existing event
  ///
  /// Uses ETag for optimistic locking if available
  Future<CalendarEvent> update(CalendarEvent event) async {
    if (event.href == null) {
      throw const CalDavException('Event href is required for update');
    }

    try {
      final response = await _client.put(
        event.href.toString(),
        body: event.toIcalendar(),
        ifMatch: event.etag, // Optimistic locking
      );

      final newEtag = response.headers.value('etag');

      return event.copyWith(etag: newEtag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Event was modified by another client. Please refresh and try again.');
      }
      if (e.response?.statusCode == 404) {
        throw const NotFoundException('Event not found');
      }
      throw CalDavException(
        'Failed to update event: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Delete an event
  Future<void> delete(CalendarEvent event) async {
    if (event.href == null) {
      throw const CalDavException('Event href is required for delete');
    }

    try {
      await _client.delete(
        event.href.toString(),
        ifMatch: event.etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Already deleted, consider success
        return;
      }
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Event was modified by another client. Please refresh and try again.');
      }
      throw CalDavException(
        'Failed to delete event: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Get multiple events by URLs (multiget)
  Future<List<CalendarEvent>> multiGet(
    Calendar calendar,
    List<Uri> eventUrls,
  ) async {
    if (eventUrls.isEmpty) return [];

    final hrefs = eventUrls.map((u) => '<D:href>${u.path}</D:href>').join('\n');

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  $hrefs
</C:calendar-multiget>''';

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final events = <CalendarEvent>[];

      for (final davResponse in multiStatus.responses) {
        final calendarData = davResponse.getProperty(
          'calendar-data',
          namespace: XmlNamespaces.caldav,
        );

        if (calendarData == null || calendarData.isEmpty) continue;

        final etag = davResponse.getProperty(
          'getetag',
          namespace: XmlNamespaces.dav,
        );

        final event = ICalendarParser.parseEvent(
          calendarData,
          calendarId: calendar.uid,
          href: calendar.href.resolve(davResponse.href),
          etag: etag,
          isReadOnly: calendar.isReadOnly,
        );

        if (event != null) events.add(event);
      }

      return events;
    } on DioException catch (e) {
      throw CalDavException(
        'Failed to get events: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Find an event by UID in a specific calendar
  ///
  /// Uses server-side filtering via calendar-query for efficiency.
  /// Returns null if no event is found.
  Future<CalendarEvent?> findByUid(Calendar calendar, String uid) async {
    final body = _buildUidQueryBody(uid);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return null;

      for (final davResponse in multiStatus.responses) {
        final calendarData = davResponse.getProperty(
          'calendar-data',
          namespace: XmlNamespaces.caldav,
        );

        if (calendarData != null && calendarData.isNotEmpty) {
          final etag = davResponse.getProperty(
            'getetag',
            namespace: XmlNamespaces.dav,
          );
          return ICalendarParser.parseEvent(
            calendarData,
            calendarId: calendar.uid,
            href: calendar.href.resolve(davResponse.href),
            etag: etag,
            isReadOnly: calendar.isReadOnly,
          );
        }
      }

      return null;
    } on DioException catch (e) {
      throw CalDavException(
        'Failed to find event by UID: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  String _buildUidQueryBody(String uid) {
    // Escape special XML characters in UID
    final escapedUid = uid
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        <C:prop-filter name="UID">
          <C:text-match collation="i;octet">$escapedUid</C:text-match>
        </C:prop-filter>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }

  String _buildCalendarQueryBody({
    DateTime? start,
    DateTime? end,
  }) {
    final timeRange = (start != null && end != null)
        ? '<C:time-range start="${_formatUtc(start)}" end="${_formatUtc(end)}"/>'
        : '';

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        $timeRange
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }

  String _formatUtc(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }
}
