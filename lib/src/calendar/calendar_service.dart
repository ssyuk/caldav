import 'package:dio/dio.dart';

import '../client/dio_webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../webdav/multistatus.dart';
import '../webdav/propfind_builder.dart';
import '../webdav/xml_namespaces.dart';
import 'calendar.dart';

/// Service for calendar CRUD operations
class CalendarService {
  final DioWebDavClient _client;
  final Uri _calendarHome;

  CalendarService(this._client, this._calendarHome);

  /// List all calendars in calendar home
  Future<List<Calendar>> list() async {
    final body = PropfindBuilder.calendarProperties();

    try {
      final response = await _client.propfind(
        _calendarHome.toString(),
        body: body,
        depth: 1,
      );

      final responseData = response.data;
      if (responseData == null || responseData.isEmpty) {
        return [];
      }

      final multiStatus = MultiStatus.fromXml(responseData);

      return multiStatus.responses
          .where((r) => r.isCalendar && r.href != _calendarHome.path)
          .map(_parseCalendar)
          .toList();
    } on DioException catch (e) {
      throw CaldavException(
        'Failed to list calendars: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    } on Exception catch (e) {
      throw CaldavException('Failed to parse calendar list: $e');
    }
  }

  /// Get a specific calendar by URL
  Future<Calendar> get(Uri calendarUrl) async {
    final body = PropfindBuilder.calendarProperties();

    try {
      final response = await _client.propfind(
        calendarUrl.toString(),
        body: body,
        depth: 0,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final davResponse = multiStatus.first;

      if (davResponse == null || !davResponse.isCalendar) {
        throw const NotFoundException('Calendar not found');
      }

      return _parseCalendar(davResponse);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const NotFoundException('Calendar not found');
      }
      throw CaldavException(
        'Failed to get calendar: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Create a new calendar
  Future<Calendar> create(
    String name, {
    String? description,
    String? color,
    String? timezone,
    List<String> supportedComponents = const ['VEVENT'],
  }) async {
    final calendarPath = _calendarHome.resolve('${_sanitizeName(name)}/');

    final body = _buildMkcalendarBody(
      name: name,
      description: description,
      color: color,
      timezone: timezone,
      supportedComponents: supportedComponents,
    );

    try {
      await _client.mkcalendar(calendarPath.toString(), body: body);

      return Calendar(
        href: calendarPath,
        displayName: name,
        description: description,
        color: color,
        timezone: timezone,
        supportedComponents: supportedComponents,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 405) {
        throw const CaldavException('Calendar already exists or creation not allowed');
      }
      throw CaldavException(
        'Failed to create calendar: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Update calendar properties
  Future<void> update(
    Calendar calendar, {
    String? displayName,
    String? description,
    String? color,
  }) async {
    final body = _buildProppatchBody(
      displayName: displayName,
      description: description,
      color: color,
    );

    try {
      await _client.proppatch(calendar.href.toString(), body: body);
    } on DioException catch (e) {
      throw CaldavException(
        'Failed to update calendar: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Delete a calendar
  Future<void> delete(Calendar calendar) async {
    try {
      await _client.delete(calendar.href.toString());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const NotFoundException('Calendar not found');
      }
      throw CaldavException(
        'Failed to delete calendar: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Calendar _parseCalendar(DavResponse response) {
    final displayName = response.getProperty(
          'displayname',
          namespace: XmlNamespaces.dav,
        ) ??
        'Untitled';

    final description = response.getProperty(
      'calendar-description',
      namespace: XmlNamespaces.caldav,
    );

    final color = response.getProperty(
      'calendar-color',
      namespace: XmlNamespaces.apple,
    );

    final timezone = response.getProperty(
      'calendar-timezone',
      namespace: XmlNamespaces.caldav,
    );

    final ctag = response.getProperty(
      'getctag',
      namespace: XmlNamespaces.calendarServer,
    );

    // Parse supported components
    final supportedComponentsElement = response.getPropertyElement(
      'supported-calendar-component-set',
      namespace: XmlNamespaces.caldav,
    );

    final supportedComponents = supportedComponentsElement?.childElements
            .where((e) =>
                e.localName == 'comp' &&
                e.namespaceUri == XmlNamespaces.caldav)
            .map((e) => e.getAttribute('name') ?? '')
            .where((name) => name.isNotEmpty)
            .toList() ??
        ['VEVENT'];

    return Calendar(
      href: _calendarHome.resolve(response.href),
      displayName: displayName,
      description: description,
      color: color,
      timezone: timezone,
      ctag: ctag,
      supportedComponents: supportedComponents,
    );
  }

  String _sanitizeName(String name) {
    // Remove special characters and spaces
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _buildMkcalendarBody({
    required String name,
    String? description,
    String? color,
    String? timezone,
    List<String>? supportedComponents,
  }) {
    final props = StringBuffer();
    props.writeln('        <D:displayname>$name</D:displayname>');

    if (description != null) {
      props.writeln(
          '        <C:calendar-description>$description</C:calendar-description>');
    }

    if (color != null) {
      props.writeln('        <A:calendar-color>$color</A:calendar-color>');
    }

    if (timezone != null) {
      props.writeln(
          '        <C:calendar-timezone>$timezone</C:calendar-timezone>');
    }

    if (supportedComponents != null && supportedComponents.isNotEmpty) {
      props.writeln('        <C:supported-calendar-component-set>');
      for (final comp in supportedComponents) {
        props.writeln('          <C:comp name="$comp"/>');
      }
      props.writeln('        </C:supported-calendar-component-set>');
    }

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:A="http://apple.com/ns/ical/">
  <D:set>
    <D:prop>
$props    </D:prop>
  </D:set>
</C:mkcalendar>''';
  }

  String _buildProppatchBody({
    String? displayName,
    String? description,
    String? color,
  }) {
    final props = StringBuffer();

    if (displayName != null) {
      props.writeln('        <D:displayname>$displayName</D:displayname>');
    }

    if (description != null) {
      props.writeln(
          '        <C:calendar-description>$description</C:calendar-description>');
    }

    if (color != null) {
      props.writeln('        <A:calendar-color>$color</A:calendar-color>');
    }

    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:A="http://apple.com/ns/ical/">
  <D:set>
    <D:prop>
$props    </D:prop>
  </D:set>
</D:propertyupdate>''';
  }
}
