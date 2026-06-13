import 'package:dio/dio.dart';

import '../calendar/calendar.dart';
import '../client/dio_webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../utils/icalendar_utils.dart';
import '../webdav/multistatus.dart';
import '../webdav/xml_namespaces.dart';
import 'icalendar_parser.dart';
import 'todo.dart';

/// Service for VTODO (to-do) CRUD operations.
///
/// Mirrors [EventService] but targets VTODO components.
class TodoService {
  final DioWebDavClient _client;

  TodoService(this._client);

  CalendarTodo? _parseTodoFromResponse(
    DavResponse davResponse,
    Calendar calendar,
  ) {
    final calendarData = davResponse.getProperty(
      'calendar-data',
      namespace: XmlNamespaces.caldav,
    );

    if (calendarData == null || calendarData.isEmpty) return null;

    final etag = davResponse.getProperty(
      'getetag',
      namespace: XmlNamespaces.dav,
    );

    return ICalendarParser.parseTodo(
      calendarData,
      calendarId: calendar.uid,
      href: calendar.href.resolve(davResponse.href),
      etag: etag,
      isReadOnly: calendar.isReadOnly,
    );
  }

  List<CalendarTodo> _parseTodosFromResponses(
    List<DavResponse> responses,
    Calendar calendar,
  ) {
    final todos = <CalendarTodo>[];
    for (final davResponse in responses) {
      final todo = _parseTodoFromResponse(davResponse, calendar);
      if (todo != null) todos.add(todo);
    }
    return todos;
  }

  /// List todos in a calendar.
  ///
  /// [start]/[end] apply a server-side time-range filter when both are given;
  /// otherwise all todos are returned (recommended, since many todos have no
  /// DTSTART/DUE and would be missed by a time-range filter).
  Future<List<CalendarTodo>> list(
    Calendar calendar, {
    DateTime? start,
    DateTime? end,
  }) async {
    final body = buildCalendarQueryBody(start: start, end: end);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return [];

      final todos = _parseTodosFromResponses(multiStatus.responses, calendar);
      if (todos.isNotEmpty) return todos;

      // Servers that return hrefs without calendar-data (Naver-style):
      final urlsWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .toList();

      if (urlsWithoutData.isNotEmpty) {
        return _fetchWithMultiget(calendar, urlsWithoutData);
      }

      return [];
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to list todos');
    }
  }

  Future<List<CalendarTodo>> _fetchWithMultiget(
    Calendar calendar,
    List<String> todoPaths,
  ) async {
    if (todoPaths.isEmpty) return [];

    final hrefs = todoPaths
        .map((p) => '<D:href>${ICalendarUtils.escapeXml(p)}</D:href>')
        .join('\n');

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
      return _parseTodosFromResponses(multiStatus.responses, calendar);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to fetch todos');
    }
  }

  /// Create a new todo. Returns the created todo with href and etag.
  Future<CalendarTodo> create(Calendar calendar, CalendarTodo todo) async {
    final todoPath = calendar.href.resolve('${todo.uid}.ics');

    try {
      final response = await _client.put(
        todoPath.toString(),
        body: todo.toIcalendar(),
        ifNoneMatch: '*',
      );

      final etag = response.headers.value('etag');
      return todo.copyWith(href: todoPath, etag: etag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException('Todo already exists');
      }
      throw _mapException(e, 'Failed to create todo');
    }
  }

  /// Update an existing todo (ETag optimistic locking when available).
  Future<CalendarTodo> update(CalendarTodo todo) async {
    if (todo.href == null) {
      throw const CalDavException('Todo href is required for update');
    }

    try {
      final response = await _client.put(
        todo.href.toString(),
        body: todo.toIcalendar(),
        ifMatch: todo.etag,
      );

      final newEtag = response.headers.value('etag');
      return todo.copyWith(etag: newEtag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Todo was modified by another client. Please refresh and try again.');
      }
      throw _mapException(e, 'Failed to update todo');
    }
  }

  /// Delete a todo.
  Future<void> delete(CalendarTodo todo) async {
    if (todo.href == null) {
      throw const CalDavException('Todo href is required for delete');
    }

    try {
      await _client.delete(
        todo.href.toString(),
        ifMatch: todo.etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return; // already deleted
      }
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Todo was modified by another client. Please refresh and try again.');
      }
      throw _mapException(e, 'Failed to delete todo');
    }
  }

  /// Find a todo by UID in a specific calendar. Returns null if not found.
  Future<CalendarTodo?> findByUid(Calendar calendar, String uid) async {
    final body = buildUidQueryBody(uid);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return null;

      for (final davResponse in multiStatus.responses) {
        final todo = _parseTodoFromResponse(davResponse, calendar);
        if (todo != null) return todo;
      }

      final urlWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .firstOrNull;

      if (urlWithoutData != null) {
        final todos = await _fetchWithMultiget(calendar, [urlWithoutData]);
        return todos.isNotEmpty ? todos.first : null;
      }

      return null;
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to find todo by UID');
    }
  }

  static CalDavException _mapException(DioException e, String context) {
    return switch (e.response?.statusCode) {
      401 => const AuthenticationException(),
      403 => const ForbiddenException(),
      404 => const NotFoundException(),
      _ => CalDavException(
          '$context: ${e.message}',
          statusCode: e.response?.statusCode,
        ),
    };
  }

  /// Build a calendar-query REPORT body filtering on VTODO.
  ///
  /// Exposed as static for unit testing of the request body.
  static String buildCalendarQueryBody({
    DateTime? start,
    DateTime? end,
  }) {
    final timeRange = (start != null && end != null)
        ? '<C:time-range start="${ICalendarUtils.formatUtc(start)}" end="${ICalendarUtils.formatUtc(end)}"/>'
        : '';

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VTODO">
        $timeRange
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }

  /// Build a calendar-query REPORT body matching a VTODO by UID.
  static String buildUidQueryBody(String uid) {
    final escapedUid = ICalendarUtils.escapeXml(uid);

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VTODO">
        <C:prop-filter name="UID">
          <C:text-match collation="i;octet">$escapedUid</C:text-match>
        </C:prop-filter>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }
}
