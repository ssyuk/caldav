import 'event.dart';

/// Parser for iCalendar (RFC 5545) data
class ICalendarParser {
  ICalendarParser._();

  /// Parse iCalendar string to CalendarEvent
  ///
  /// [icalendar] Raw iCalendar string
  /// [calendarId] Calendar ID that this event belongs to
  /// [href] Resource URL
  /// [etag] Entity tag
  /// [isReadOnly] Whether the event is read-only (inherited from calendar)
  static CalendarEvent? parseEvent(
    String icalendar, {
    required String calendarId,
    Uri? href,
    String? etag,
    bool isReadOnly = false,
  }) {
    final lines = _unfoldLines(icalendar);
    final eventLines = _extractComponent(lines, 'VEVENT');

    if (eventLines.isEmpty) return null;

    final properties = _parseProperties(eventLines);

    // Parse required fields
    final uid = properties['UID'];
    final summary = properties['SUMMARY'] ?? 'Untitled';

    if (uid == null) return null;

    // Parse DTSTART
    final dtstart = _parseDateTime(
      properties['DTSTART'],
      properties['DTSTART;VALUE'],
    );

    if (dtstart == null) return null;

    // Parse DTEND (optional)
    final dtend = _parseDateTime(
      properties['DTEND'],
      properties['DTEND;VALUE'],
    );

    // Check if all-day event
    final isAllDay = properties['DTSTART;VALUE'] == 'DATE' ||
        (properties['DTSTART']?.length == 8);

    // Parse recurrence fields
    final rrule = properties['RRULE'];
    final recurrenceId = properties['RECURRENCE-ID'];

    // Parse EXDATE (may have multiple values separated by comma, or multiple EXDATE lines)
    final exdate = _parseExdate(eventLines);

    return CalendarEvent(
      uid: uid,
      calendarId: calendarId,
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
      isReadOnly: isReadOnly,
      rrule: rrule,
      recurrenceId: recurrenceId,
      exdate: exdate,
    );
  }

  /// Parse multiple events from iCalendar
  static List<CalendarEvent> parseEvents(
    String icalendar, {
    required String calendarId,
    Uri? baseHref,
    bool isReadOnly = false,
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
          calendarId: calendarId,
          isReadOnly: isReadOnly,
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

  /// Parse datetime value to UTC DateTime
  static DateTime? _parseDateTime(
    String? value,
    String? valueType,
  ) {
    if (value == null || value.isEmpty) return null;

    try {
      // UTC format: 20240115T100000Z
      if (value.endsWith('Z')) {
        return _parseIsoBasic(value.substring(0, value.length - 1), isUtc: true);
      }

      // Date only (all-day): 20240115
      if (value.length == 8 || valueType == 'DATE') {
        final cleanValue = value.length > 8 ? value.substring(0, 8) : value;
        final year = int.parse(cleanValue.substring(0, 4));
        final month = int.parse(cleanValue.substring(4, 6));
        final day = int.parse(cleanValue.substring(6, 8));
        return DateTime.utc(year, month, day);
      }

      // Local time - convert to UTC
      return _parseIsoBasic(value, isUtc: false)?.toUtc();
    } catch (e) {
      return null;
    }
  }

  /// Parse ISO basic format: 20240115T100000
  static DateTime? _parseIsoBasic(String value, {bool isUtc = false}) {
    try {
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
        return isUtc
            ? DateTime.utc(year, month, day, hour, minute, second)
            : DateTime(year, month, day, hour, minute, second);
      }

      return isUtc ? DateTime.utc(year, month, day) : DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  /// Unescape iCalendar text
  static String _unescapeIcalText(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }

  /// Parse EXDATE values from event lines
  /// EXDATE can appear multiple times and can have comma-separated values
  /// Example: EXDATE:20240115T100000Z,20240116T100000Z
  /// Example: EXDATE;VALUE=DATE:20240115,20240116
  static List<String>? _parseExdate(List<String> lines) {
    final exdates = <String>[];

    for (final line in lines) {
      if (line.startsWith('EXDATE')) {
        final colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          final value = line.substring(colonIndex + 1).trim();
          // Split by comma for multiple dates in one EXDATE line
          final dates = value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
          exdates.addAll(dates);
        }
      }
    }

    return exdates.isEmpty ? null : exdates;
  }
}
