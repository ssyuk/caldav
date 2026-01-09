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
      throw CalDavException(
        'Failed to list calendars: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    } on Exception catch (e) {
      throw CalDavException('Failed to parse calendar list: $e');
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
      throw CalDavException(
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

      // Fetch the created calendar to get the server-assigned uid
      return await get(calendarPath);
    } on DioException catch (e) {
      if (e.response?.statusCode == 405) {
        throw const CalDavException('Calendar already exists or creation not allowed');
      }
      throw CalDavException(
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
      throw CalDavException(
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
      throw CalDavException(
        'Failed to delete calendar: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Calendar _parseCalendar(DavResponse response) {
    final uid = response.getProperty(
      'geteuid',
      namespace: XmlNamespaces.dav,
    );

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

    // Parse privileges to determine read-only status
    final isReadOnly = _parseIsReadOnly(response);

    return Calendar(
      uid: uid ?? response.href,
      href: _calendarHome.resolve(response.href),
      displayName: displayName,
      description: description,
      color: color,
      timezone: timezone,
      ctag: ctag,
      supportedComponents: supportedComponents,
      isReadOnly: isReadOnly,
    );
  }

  /// Parse current-user-privilege-set to determine if calendar is read-only
  ///
  /// A calendar is read-only if it lacks any write privileges:
  /// - write
  /// - write-content
  /// - bind (add resources)
  /// - unbind (remove resources)
  bool _parseIsReadOnly(DavResponse response) {
    final privilegeSetElement = response.getPropertyElement(
      'current-user-privilege-set',
      namespace: XmlNamespaces.dav,
    );

    // If no privilege-set returned, assume writable (server may not support ACL)
    if (privilegeSetElement == null) {
      return false;
    }

    // Write privileges that indicate the calendar is writable
    const writePrivileges = {'write', 'write-content', 'bind', 'unbind', 'all'};

    // Look for any write privilege in the privilege set
    for (final privilegeElement in privilegeSetElement.childElements) {
      if (privilegeElement.localName != 'privilege' ||
          privilegeElement.namespaceUri != XmlNamespaces.dav) {
        continue;
      }

      for (final privilege in privilegeElement.childElements) {
        if (privilege.namespaceUri == XmlNamespaces.dav &&
            writePrivileges.contains(privilege.localName)) {
          return false; // Has write privilege, not read-only
        }
      }
    }

    // No write privileges found, calendar is read-only
    return true;
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
