/// Represents a calendar event (VEVENT)
class CalendarEvent {
  /// Unique identifier for the event
  final String uid;

  /// Calendar ID that this event belongs to
  final String calendarId;

  /// Resource URL (set after creation)
  final Uri? href;

  /// Entity tag for concurrency control
  final String? etag;

  /// Event start time (UTC)
  final DateTime start;

  /// Event end time (UTC)
  final DateTime? end;

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

  /// Whether this event is read-only (inherited from calendar)
  final bool isReadOnly;

  const CalendarEvent({
    required this.uid,
    required this.calendarId,
    this.href,
    this.etag,
    required this.start,
    this.end,
    required this.summary,
    this.description,
    this.location,
    this.isAllDay = false,
    this.rawIcalendar,
    this.isReadOnly = false,
  });

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
    DateTime? start,
    DateTime? end,
    String? summary,
    String? description,
    String? location,
    bool? isAllDay,
    String? rawIcalendar,
    bool? isReadOnly,
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
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }

  /// Convert to iCalendar format
  String toIcalendar() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:$uid');
    buffer.writeln('DTSTAMP:${_formatDateTimeUtc(DateTime.now().toUtc())}');

    if (isAllDay) {
      buffer.writeln('DTSTART;VALUE=DATE:${_formatDate(start)}');
      if (end != null) {
        buffer.writeln('DTEND;VALUE=DATE:${_formatDate(end!)}');
      }
    } else {
      buffer.writeln('DTSTART:${_formatDateTimeUtc(start.toUtc())}');
      if (end != null) {
        buffer.writeln('DTEND:${_formatDateTimeUtc(end!.toUtc())}');
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
  String _formatDateTimeUtc(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}T'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }

  /// Format: 20240115 (date only)
  String _formatDate(DateTime dt) {
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
