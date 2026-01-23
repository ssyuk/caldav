import '../utils/icalendar_utils.dart';

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

  /// Recurrence rule (RFC 5545 RRULE)
  /// Example: "FREQ=DAILY;INTERVAL=1;COUNT=10"
  final String? rrule;

  /// Recurrence ID for modified instances (RFC 5545 RECURRENCE-ID)
  /// Contains the original occurrence date of a modified recurring instance
  final String? recurrenceId;

  /// Exception dates (RFC 5545 EXDATE)
  /// List of dates excluded from the recurrence set
  final List<String>? exdate;

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
    this.rrule,
    this.recurrenceId,
    this.exdate,
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
    String? rrule,
    String? recurrenceId,
    List<String>? exdate,
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
      rrule: rrule ?? this.rrule,
      recurrenceId: recurrenceId ?? this.recurrenceId,
      exdate: exdate ?? this.exdate,
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
    buffer.writeln('DTSTAMP:${ICalendarUtils.formatUtc(DateTime.now().toUtc())}');

    if (isAllDay) {
      buffer.writeln('DTSTART;VALUE=DATE:${ICalendarUtils.formatDate(start)}');
      if (end != null) {
        buffer.writeln('DTEND;VALUE=DATE:${ICalendarUtils.formatDate(end!)}');
      }
    } else {
      buffer.writeln('DTSTART:${ICalendarUtils.formatUtc(start.toUtc())}');
      if (end != null) {
        buffer.writeln('DTEND:${ICalendarUtils.formatUtc(end!.toUtc())}');
      }
    }

    buffer.writeln('SUMMARY:${ICalendarUtils.escapeText(summary)}');

    if (description != null && description!.isNotEmpty) {
      buffer.writeln('DESCRIPTION:${ICalendarUtils.escapeText(description!)}');
    }

    if (location != null && location!.isNotEmpty) {
      buffer.writeln('LOCATION:${ICalendarUtils.escapeText(location!)}');
    }

    if (rrule != null && rrule!.isNotEmpty) {
      buffer.writeln('RRULE:$rrule');
    }

    if (recurrenceId != null && recurrenceId!.isNotEmpty) {
      buffer.writeln('RECURRENCE-ID:$recurrenceId');
    }

    if (exdate != null && exdate!.isNotEmpty) {
      buffer.writeln('EXDATE:${exdate!.join(',')}');
    }

    buffer.writeln('END:VEVENT');
    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
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
