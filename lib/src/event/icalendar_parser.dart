import 'package:timezone/timezone.dart' as tz;

import 'event.dart';

/// Parser for iCalendar (RFC 5545) data
class ICalendarParser {
  ICalendarParser._();

  /// Parse iCalendar string to CalendarEvent
  ///
  /// [icalendar] Raw iCalendar string
  /// [href] Resource URL
  /// [etag] Entity tag
  /// [defaultLocation] Default timezone if not specified
  static CalendarEvent? parseEvent(
    String icalendar, {
    Uri? href,
    String? etag,
    tz.Location? defaultLocation,
  }) {
    final lines = _unfoldLines(icalendar);
    final eventLines = _extractComponent(lines, 'VEVENT');

    if (eventLines.isEmpty) return null;

    final properties = _parseProperties(eventLines);
    final location = defaultLocation ?? tz.local;

    // Parse required fields
    final uid = properties['UID'];
    final summary = properties['SUMMARY'] ?? 'Untitled';

    if (uid == null) return null;

    // Parse DTSTART
    final dtstart = _parseDateTime(
      properties['DTSTART'],
      properties['DTSTART;VALUE'],
      _extractTzid(properties, 'DTSTART'),
      location,
    );

    if (dtstart == null) return null;

    // Parse DTEND (optional)
    final dtend = _parseDateTime(
      properties['DTEND'],
      properties['DTEND;VALUE'],
      _extractTzid(properties, 'DTEND'),
      location,
    );

    // Check if all-day event
    final isAllDay = properties['DTSTART;VALUE'] == 'DATE' ||
        (properties['DTSTART']?.length == 8);

    return CalendarEvent(
      uid: uid,
      href: href,
      etag: etag,
      start: dtstart,
      end: dtend,
      summary: _unescapeIcalText(summary),
      description: properties['DESCRIPTION'] != null
          ? _unescapeIcalText(properties['DESCRIPTION']!)
          : null,
      location: properties['LOCATION'] != null
          ? _unescapeIcalText(properties['LOCATION']!)
          : null,
      isAllDay: isAllDay,
      rawIcalendar: icalendar,
    );
  }

  /// Parse multiple events from iCalendar
  static List<CalendarEvent> parseEvents(
    String icalendar, {
    Uri? baseHref,
    tz.Location? defaultLocation,
  }) {
    final lines = _unfoldLines(icalendar);
    final events = <CalendarEvent>[];

    var inEvent = false;
    var eventLines = <String>[];

    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        eventLines = [];
      } else if (line == 'END:VEVENT') {
        inEvent = false;
        final event = parseEvent(
          'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\n${eventLines.join('\n')}\nEND:VEVENT\nEND:VCALENDAR',
          defaultLocation: defaultLocation,
        );
        if (event != null) events.add(event);
      } else if (inEvent) {
        eventLines.add(line);
      }
    }

    return events;
  }

  /// Unfold continuation lines (RFC 5545 Section 3.1)
  static List<String> _unfoldLines(String icalendar) {
    // Replace CRLF + space/tab with empty string
    final unfolded = icalendar
        .replaceAll('\r\n ', '')
        .replaceAll('\r\n\t', '')
        .replaceAll('\n ', '')
        .replaceAll('\n\t', '');

    return unfolded.split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).toList();
  }

  /// Extract lines for a specific component
  static List<String> _extractComponent(List<String> lines, String component) {
    final result = <String>[];
    var inComponent = false;

    for (final line in lines) {
      if (line == 'BEGIN:$component') {
        inComponent = true;
      } else if (line == 'END:$component') {
        break;
      } else if (inComponent) {
        result.add(line);
      }
    }

    return result;
  }

  /// Parse properties from lines
  static Map<String, String> _parseProperties(List<String> lines) {
    final properties = <String, String>{};

    for (final line in lines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex == -1) continue;

      final key = line.substring(0, colonIndex);
      final value = line.substring(colonIndex + 1);

      // Handle parameters (e.g., DTSTART;TZID=America/New_York:20240115T100000)
      final semicolonIndex = key.indexOf(';');
      if (semicolonIndex != -1) {
        final baseName = key.substring(0, semicolonIndex);
        final params = key.substring(semicolonIndex + 1);

        properties[baseName] = value;

        // Store parameters separately
        for (final param in params.split(';')) {
          final eqIndex = param.indexOf('=');
          if (eqIndex != -1) {
            final paramName = param.substring(0, eqIndex);
            final paramValue = param.substring(eqIndex + 1);
            properties['$baseName;$paramName'] = paramValue;
          } else {
            // VALUE=DATE style without explicit name
            properties['$baseName;VALUE'] = param;
          }
        }
      } else {
        properties[key] = value;
      }
    }

    return properties;
  }

  /// Extract TZID parameter for a property
  static String? _extractTzid(Map<String, String> properties, String propName) {
    return properties['$propName;TZID'];
  }

  /// Parse datetime value
  static tz.TZDateTime? _parseDateTime(
    String? value,
    String? valueType,
    String? tzid,
    tz.Location defaultLocation,
  ) {
    if (value == null || value.isEmpty) return null;

    try {
      // UTC format: 20240115T100000Z
      if (value.endsWith('Z')) {
        final dt = _parseIsoBasic(value.substring(0, value.length - 1));
        return tz.TZDateTime.utc(
            dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
      }

      // Date only (all-day): 20240115
      if (value.length == 8 || valueType == 'DATE') {
        final cleanValue = value.length > 8 ? value.substring(0, 8) : value;
        final year = int.parse(cleanValue.substring(0, 4));
        final month = int.parse(cleanValue.substring(4, 6));
        final day = int.parse(cleanValue.substring(6, 8));

        final location = tzid != null ? tz.getLocation(tzid) : defaultLocation;
        return tz.TZDateTime(location, year, month, day);
      }

      // Local time with timezone
      final location = tzid != null ? tz.getLocation(tzid) : defaultLocation;
      final dt = _parseIsoBasic(value);
      return tz.TZDateTime(
          location, dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
    } catch (e) {
      return null;
    }
  }

  /// Parse ISO basic format: 20240115T100000
  static DateTime _parseIsoBasic(String value) {
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(4, 6));
    final day = int.parse(value.substring(6, 8));

    if (value.length > 8 && value.contains('T')) {
      final timeStart = value.indexOf('T') + 1;
      final hour = int.parse(value.substring(timeStart, timeStart + 2));
      final minute = int.parse(value.substring(timeStart + 2, timeStart + 4));
      final second = value.length >= timeStart + 6
          ? int.parse(value.substring(timeStart + 4, timeStart + 6))
          : 0;
      return DateTime(year, month, day, hour, minute, second);
    }

    return DateTime(year, month, day);
  }

  /// Unescape iCalendar text
  static String _unescapeIcalText(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }
}
