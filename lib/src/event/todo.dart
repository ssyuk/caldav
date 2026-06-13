import '../utils/icalendar_utils.dart';
import 'calendar_component.dart';

/// RFC 5545 VTODO status values.
enum TodoStatus { needsAction, inProcess, completed, cancelled }

/// Represents a calendar to-do item (VTODO).
class CalendarTodo extends CalendarComponent {
  /// Start of the task (RFC 5545 DTSTART) — optional.
  final DateTime? dtstart;

  /// Deadline of the task (RFC 5545 DUE) — optional.
  final DateTime? due;

  /// Whether dtstart/due are date-only (all-day) values.
  final bool isAllDay;

  /// Task status (RFC 5545 STATUS). Defaults to [TodoStatus.needsAction].
  final TodoStatus status;

  /// Completion timestamp (RFC 5545 COMPLETED).
  final DateTime? completed;

  /// Completion percentage 0–100 (RFC 5545 PERCENT-COMPLETE).
  final int? percentComplete;

  /// Priority 0–9 (RFC 5545 PRIORITY); 0 means undefined.
  final int? priority;

  const CalendarTodo({
    required super.uid,
    required super.calendarId,
    super.href,
    super.etag,
    required super.summary,
    super.description,
    super.location,
    this.dtstart,
    this.due,
    this.isAllDay = false,
    this.status = TodoStatus.needsAction,
    this.completed,
    this.percentComplete,
    this.priority,
    super.rawIcalendar,
    super.isReadOnly = false,
    super.rrule,
    super.recurrenceId,
    super.exdate,
  });

  /// Convenience for simple consumers: a todo is "done" if its status is
  /// completed, it has a COMPLETED timestamp, or PERCENT-COMPLETE is 100.
  bool get isCompleted =>
      status == TodoStatus.completed ||
      completed != null ||
      percentComplete == 100;

  /// Create a copy with updated fields.
  CalendarTodo copyWith({
    String? uid,
    String? calendarId,
    Uri? href,
    String? etag,
    String? summary,
    String? description,
    String? location,
    DateTime? dtstart,
    DateTime? due,
    bool? isAllDay,
    TodoStatus? status,
    DateTime? completed,
    int? percentComplete,
    int? priority,
    String? rawIcalendar,
    bool? isReadOnly,
    String? rrule,
    String? recurrenceId,
    List<String>? exdate,
  }) {
    return CalendarTodo(
      uid: uid ?? this.uid,
      calendarId: calendarId ?? this.calendarId,
      href: href ?? this.href,
      etag: etag ?? this.etag,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      dtstart: dtstart ?? this.dtstart,
      due: due ?? this.due,
      isAllDay: isAllDay ?? this.isAllDay,
      status: status ?? this.status,
      completed: completed ?? this.completed,
      percentComplete: percentComplete ?? this.percentComplete,
      priority: priority ?? this.priority,
      rawIcalendar: rawIcalendar ?? this.rawIcalendar,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      rrule: rrule ?? this.rrule,
      recurrenceId: recurrenceId ?? this.recurrenceId,
      exdate: exdate ?? this.exdate,
    );
  }

  @override
  String toIcalendar() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');

    buffer.writeln('BEGIN:VTODO');
    buffer.writeln('UID:$uid');
    buffer.writeln('DTSTAMP:${ICalendarUtils.formatUtc(DateTime.now().toUtc())}');

    if (dtstart != null) {
      if (isAllDay) {
        buffer.writeln('DTSTART;VALUE=DATE:${ICalendarUtils.formatDate(dtstart!)}');
      } else {
        buffer.writeln('DTSTART:${ICalendarUtils.formatUtc(dtstart!.toUtc())}');
      }
    }

    // DUE is the deadline instant, not an exclusive end — no +1 day shift.
    if (due != null) {
      if (isAllDay) {
        buffer.writeln('DUE;VALUE=DATE:${ICalendarUtils.formatDate(due!)}');
      } else {
        buffer.writeln('DUE:${ICalendarUtils.formatUtc(due!.toUtc())}');
      }
    }

    buffer.writeln('SUMMARY:${ICalendarUtils.escapeText(summary)}');

    if (description != null && description!.isNotEmpty) {
      buffer.writeln('DESCRIPTION:${ICalendarUtils.escapeText(description!)}');
    }

    if (location != null && location!.isNotEmpty) {
      buffer.writeln('LOCATION:${ICalendarUtils.escapeText(location!)}');
    }

    if (status != TodoStatus.needsAction) {
      buffer.writeln('STATUS:${_statusToIcal(status)}');
    }

    if (completed != null) {
      buffer.writeln('COMPLETED:${ICalendarUtils.formatUtc(completed!.toUtc())}');
    }

    if (percentComplete != null) {
      buffer.writeln('PERCENT-COMPLETE:$percentComplete');
    }

    if (priority != null && priority != 0) {
      buffer.writeln('PRIORITY:$priority');
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

    buffer.writeln('END:VTODO');
    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
  }

  static String _statusToIcal(TodoStatus status) => switch (status) {
        TodoStatus.needsAction => 'NEEDS-ACTION',
        TodoStatus.inProcess => 'IN-PROCESS',
        TodoStatus.completed => 'COMPLETED',
        TodoStatus.cancelled => 'CANCELLED',
      };

  @override
  String toString() =>
      'CalendarTodo(uid: $uid, summary: $summary, due: $due, status: $status)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarTodo && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
