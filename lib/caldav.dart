/// A Dart client library for interacting with CalDAV servers.
///
/// This library provides a high-level API for CalDAV operations including:
/// - Server discovery (RFC 6764)
/// - Calendar CRUD operations
/// - Event CRUD operations with iCalendar support
/// - Timezone-aware datetime handling
///
/// ## Getting Started
///
/// ```dart
/// import 'package:caldav/caldav.dart';
///
/// void main() async {
///   final client = await CaldavClient.connect(
///     baseUrl: 'https://caldav.example.com',
///     username: 'user@example.com',
///     password: 'password',
///   );
///
///   try {
///     final calendars = await client.getCalendars();
///     for (final cal in calendars) {
///       print('Calendar: ${cal.displayName}');
///
///       final events = await client.getEvents(cal);
///       for (final event in events) {
///         print('  Event: ${event.summary} at ${event.start}');
///       }
///     }
///   } finally {
///     client.close();
///   }
/// }
/// ```
library;

// Main client
export 'src/caldav_client.dart' show CalDavClient;
// Models
export 'src/calendar/calendar.dart' show Calendar;
export 'src/discovery/discovery_result.dart' show DiscoveryResult;
export 'src/event/event.dart' show CalendarEvent;
// Exceptions
export 'src/exceptions/caldav_exception.dart'
    show
        CaldavException,
        AuthenticationException,
        NotFoundException,
        ConflictException,
        DiscoveryException,
        ParseException;
