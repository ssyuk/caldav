import 'package:timezone/timezone.dart' as tz;

/// Represents a calendar event (VEVENT)
class CalendarEvent {
  /// Unique identifier for the event
  final String uid;

  /// Calendar ID that this event belongs to
  final String? calendarId;

  /// Resource URL (set after creation)
  final Uri? href;

  /// Entity tag for concurrency control
  final String? etag;

  /// Event start time
  final tz.TZDateTime start;

  /// Event end time
  final tz.TZDateTime? end;

  /// Event title/summary
  final String summary;

  /// Event description
  final String? description;

  /// Event location
  final String? location;

  /// Whether this is an all-day event
  final bool isAllDay;

  /// Raw iCalendar data (preserved from server)
  final String? rawIcalendar;

  const CalendarEvent({
    required this.uid,
    this.calendarId,
    this.href,
    this.etag,
    required this.start,
    this.end,
    required this.summary,
    this.description,
    this.location,
    this.isAllDay = false,
    this.rawIcalendar,
  });

  /// Get timezone ID (IANA format)
  String get timezoneId => start.location.name;

  /// Event duration
  Duration? get duration {
    if (end == null) return null;
    return end!.difference(start);
  }

  /// Create a copy with updated fields
  CalendarEvent copyWith({
    String? uid,
    String? calendarId,
    Uri? href,
    String? etag,
    tz.TZDateTime? start,
    tz.TZDateTime? end,
    String? summary,
    String? description,
    String? location,
    bool? isAllDay,
    String? rawIcalendar,
  }) {
    return CalendarEvent(
      uid: uid ?? this.uid,
      calendarId: calendarId ?? this.calendarId,
      href: href ?? this.href,
      etag: etag ?? this.etag,
      start: start ?? this.start,
      end: end ?? this.end,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      isAllDay: isAllDay ?? this.isAllDay,
      rawIcalendar: rawIcalendar ?? this.rawIcalendar,
    );
  }

  /// Convert to iCalendar format
  String toIcalendar() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');

    // Add VTIMEZONE if not UTC
    if (!start.isUtc && start.location != tz.UTC) {
      buffer.write(_buildVTimezone(start.location));
    }

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:$uid');
    buffer.writeln('DTSTAMP:${_formatDateTimeUtc(tz.TZDateTime.now(tz.UTC))}');

    if (isAllDay) {
      buffer.writeln('DTSTART;VALUE=DATE:${_formatDate(start)}');
      if (end != null) {
        buffer.writeln('DTEND;VALUE=DATE:${_formatDate(end!)}');
      }
    } else if (start.isUtc || start.location == tz.UTC) {
      buffer.writeln('DTSTART:${_formatDateTimeUtc(start)}');
      if (end != null) {
        buffer.writeln('DTEND:${_formatDateTimeUtc(end!)}');
      }
    } else {
      buffer.writeln(
          'DTSTART;TZID=${start.location.name}:${_formatDateTimeLocal(start)}');
      if (end != null) {
        buffer.writeln(
            'DTEND;TZID=${end!.location.name}:${_formatDateTimeLocal(end!)}');
      }
    }

    buffer.writeln('SUMMARY:${_escapeIcalText(summary)}');

    if (description != null && description!.isNotEmpty) {
      buffer.writeln('DESCRIPTION:${_escapeIcalText(description!)}');
    }

    if (location != null && location!.isNotEmpty) {
      buffer.writeln('LOCATION:${_escapeIcalText(location!)}');
    }

    buffer.writeln('END:VEVENT');
    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
  }

  /// Format: 20240115T100000Z (UTC)
  String _formatDateTimeUtc(tz.TZDateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  /// Format: 20240115T100000 (local time)
  String _formatDateTimeLocal(tz.TZDateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}T'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  /// Format: 20240115 (date only)
  String _formatDate(tz.TZDateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  /// Escape special characters in iCalendar text
  String _escapeIcalText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('\n', '\\n')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;');
  }

  /// Build simplified VTIMEZONE component
  String _buildVTimezone(tz.Location location) {
    // Note: Full VTIMEZONE requires DST transition rules
    // This is a simplified version
    return '''BEGIN:VTIMEZONE
TZID:${location.name}
BEGIN:STANDARD
DTSTART:19700101T000000
TZOFFSETFROM:+0000
TZOFFSETTO:+0000
END:STANDARD
END:VTIMEZONE
''';
  }

  @override
  String toString() {
    return 'CalendarEvent(uid: $uid, summary: $summary, start: $start)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarEvent && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
