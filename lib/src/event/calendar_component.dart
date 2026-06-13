/// Base class for iCalendar components shared by VEVENT and VTODO.
///
/// Holds the fields common to events and todos. Concrete subclasses
/// ([CalendarEvent], [CalendarTodo]) add their component-specific fields
/// and implement [toIcalendar].
abstract class CalendarComponent {
  /// Unique identifier (iCalendar UID)
  final String uid;

  /// Calendar ID that this component belongs to
  final String calendarId;

  /// Resource URL (set after creation)
  final Uri? href;

  /// Entity tag for concurrency control
  final String? etag;

  /// Title / summary
  final String summary;

  /// Description
  final String? description;

  /// Location
  final String? location;

  /// Whether this component is read-only (inherited from calendar)
  final bool isReadOnly;

  /// Raw iCalendar data (preserved from server)
  final String? rawIcalendar;

  /// Recurrence rule (RFC 5545 RRULE)
  final String? rrule;

  /// Recurrence ID for modified instances (RFC 5545 RECURRENCE-ID)
  final String? recurrenceId;

  /// Exception dates (RFC 5545 EXDATE)
  final List<String>? exdate;

  const CalendarComponent({
    required this.uid,
    required this.calendarId,
    this.href,
    this.etag,
    required this.summary,
    this.description,
    this.location,
    this.isReadOnly = false,
    this.rawIcalendar,
    this.rrule,
    this.recurrenceId,
    this.exdate,
  });

  /// Serialize this component to a complete VCALENDAR string.
  String toIcalendar();
}
