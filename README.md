# CalDAV

A comprehensive Dart client library for CalDAV servers (RFC 4791). Provides high-level APIs for calendar and event management.

## Features

- **Server Discovery** (RFC 6764) - Automatic endpoint detection via `.well-known/caldav`
- **Calendar Management** - List, create, update, delete calendars with unique identifiers
- **Event Management** - Full CRUD operations with iCalendar (RFC 5545) support
- **Event Search** - Find events by UID across all calendars with server-side filtering
- **Parallel Fetching** - Fetch events from multiple calendars concurrently
- **Multiple Authentication** - Basic Auth, Bearer Token (OAuth), and custom Dio
- **Conflict Detection** - ETag-based optimistic locking
- **Read-Only Protection** - ACL-based read-only detection with write guards
- **HTTPS by Default** - Secure connections enforced with opt-out for development

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  caldav: ^1.4.2+3
```

## Quick Start

```dart
import 'package:caldav/caldav.dart';

void main() async {
  // Connect with auto-discovery
  final client = await CalDavClient.connect(
    baseUrl: 'https://caldav.example.com',
    username: 'user@example.com',
    password: 'password',
  );

  try {
    // Get all calendars
    final calendars = await client.getCalendars();
    for (final cal in calendars) {
      print('${cal.displayName} (uid: ${cal.uid})');
    }

    // Query events (use UTC DateTime)
    final start = DateTime.utc(2024, 1, 1);
    final end = DateTime.utc(2024, 2, 1);

    for (final calendar in calendars) {
      final events = await client.getEvents(calendar, start: start, end: end);
      for (final event in events) {
        print('${event.summary} at ${event.start}');
      }
    }

    // Find event by UID across all calendars
    final event = await client.getEventByUid('unique-event-id');
    if (event != null) {
      print('Found: ${event.summary} in calendar ${event.calendarId}');
    }
  } finally {
    client.close();
  }
}
```

## Security

By default, only HTTPS connections are allowed to protect credentials. For local development or testing, you can disable this check:

```dart
// For development only - NOT recommended for production!
final client = await CalDavClient.connect(
  baseUrl: 'http://localhost:8080',
  username: 'test',
  password: 'test',
  allowInsecure: true,  // Allows HTTP connections
);
```

> **Warning**: Using HTTP transmits credentials in plain text and is vulnerable to man-in-the-middle attacks. Only use `allowInsecure: true` for local development.

## Authentication Methods

### Basic Authentication

```dart
final client = await CalDavClient.connect(
  baseUrl: 'https://caldav.example.com',
  username: 'user@example.com',
  password: 'password',
);
```

### Bearer Token (OAuth)

```dart
final client = CalDavClient.withToken(
  baseUrl: 'https://caldav.example.com',
  token: 'your_oauth_access_token',
);
await client.discover();
```

### Custom Dio Instance

```dart
final dio = Dio(BaseOptions(
  baseUrl: 'https://caldav.example.com',
  headers: {'Authorization': 'Custom scheme'},
));

final client = CalDavClient.withDio(
  baseUrl: 'https://caldav.example.com',
  dio: dio,
);
await client.discover();
```

## Calendar Operations

### List Calendars

```dart
final calendars = await client.getCalendars();
for (final cal in calendars) {
  print('${cal.displayName} (uid: ${cal.uid})');
  print('  URL: ${cal.href}');
  print('  Color: ${cal.color}');
  print('  Read-only: ${cal.isReadOnly}');
}
```

### Create Calendar

```dart
final calendar = await client.createCalendar(
  'Work Calendar',
  description: 'Work-related events',
  color: '#3366CC',
  timezone: 'Asia/Seoul',
);
```

### Update Calendar

```dart
await client.updateCalendar(
  calendar,
  displayName: 'Updated Name',
  color: '#FF5733',
);
```

### Delete Calendar

```dart
await client.deleteCalendar(calendar);
```

### Read-Only Calendars

Shared or subscribed calendars may be read-only. Write operations (`createEvent`, `updateEvent`, `deleteEvent`, `updateCalendar`, `deleteCalendar`) automatically throw `ForbiddenException` when attempted on read-only calendars.

```dart
final calendars = await client.getCalendars();
for (final cal in calendars) {
  if (cal.isReadOnly) {
    print('${cal.displayName} is read-only (shared or subscribed)');
  } else {
    print('${cal.displayName} is writable');
  }
}
```

## Event Operations

### Query Events

```dart
// Use UTC DateTime for time range filtering
final start = DateTime.utc(2024, 1, 1);
final end = DateTime.utc(2024, 12, 31);

final events = await client.getEvents(
  calendar,
  start: start,
  end: end,
);
```

### Get All Events (Parallel Fetch)

```dart
// Efficiently fetch all events from all calendars in parallel
final allEvents = await client.getAllEvents(
  start: DateTime.utc(2024, 1, 1),
  end: DateTime.utc(2024, 12, 31),
);
```

### Get Events from Multiple Calendars

```dart
// Fetch events from specific calendars in parallel
final eventsMap = await client.getEventsFromCalendars(
  [calendar1, calendar2, calendar3],
  start: start,
  end: end,
);

// eventsMap is Map<String, List<CalendarEvent>> keyed by calendar UID
for (final entry in eventsMap.entries) {
  print('Calendar ${entry.key}: ${entry.value.length} events');
}
```

### Find Event by UID

```dart
// Efficiently search across all calendars using server-side filtering
final event = await client.getEventByUid('unique-event-id');
if (event != null) {
  print('Found in calendar: ${event.calendarId}');
}
```

### Create Event

```dart
final event = CalendarEvent(
  uid: 'unique-event-id-${DateTime.now().millisecondsSinceEpoch}',
  calendarId: calendar.uid,
  start: DateTime.utc(2024, 6, 15, 14, 0),
  end: DateTime.utc(2024, 6, 15, 15, 0),
  summary: 'Team Meeting',
  description: 'Weekly sync',
  location: 'Conference Room A',
);

final created = await client.createEvent(calendar, event);
```

### Create All-Day Event

All-day events use **inclusive** dates. A single-day event only needs `start`:

```dart
// Single-day all-day event (June 15 only)
final singleDay = CalendarEvent(
  uid: 'single-day-event',
  calendarId: calendar.uid,
  start: DateTime.utc(2024, 6, 15),
  summary: 'Company Holiday',
  isAllDay: true,
);

// Multi-day all-day event (June 15 to June 17, inclusive)
final multiDay = CalendarEvent(
  uid: 'multi-day-event',
  calendarId: calendar.uid,
  start: DateTime.utc(2024, 6, 15),
  end: DateTime.utc(2024, 6, 17),
  summary: 'Summer Retreat',
  isAllDay: true,
);
```

> **Note**: The library handles RFC 5545 exclusive DTEND conversion automatically. You always work with inclusive dates - the library converts to/from the exclusive format required by the protocol.

### Update Event

```dart
try {
  final updated = await client.updateEvent(
    event.copyWith(summary: 'Updated Meeting Title'),
  );
} on ConflictException {
  // Event was modified by another client
  print('Conflict detected, please refresh and retry');
}
```

### Delete Event

```dart
await client.deleteEvent(event);
```

### Recurring Events

The library parses recurring event fields from iCalendar data:

```dart
final events = await client.getEvents(calendar, start: start, end: end);
for (final event in events) {
  if (event.rrule != null) {
    print('Recurring event: ${event.summary}');
    print('  Rule: ${event.rrule}');  // e.g., "FREQ=DAILY;COUNT=10"

    if (event.exdate != null) {
      print('  Excluded dates: ${event.exdate}');
    }
  }

  if (event.recurrenceId != null) {
    print('Modified instance of recurring event');
    print('  Original date: ${event.recurrenceId}');
  }
}
```

> **Note**: The library provides raw RRULE strings. For recurrence expansion, use a dedicated library like `rrule`.

## Data Models

### Calendar

| Property | Type | Description |
|----------|------|-------------|
| `uid` | `String` | Unique identifier (DAV:geteuid or href fallback) |
| `href` | `Uri` | Calendar resource URL |
| `displayName` | `String` | Display name |
| `description` | `String?` | Calendar description |
| `color` | `String?` | Color (#RRGGBB or #RRGGBBAA) |
| `timezone` | `String?` | Default timezone (IANA format) |
| `ctag` | `String?` | Collection tag for sync |
| `supportedComponents` | `List<String>` | Supported components (VEVENT, VTODO, etc.) |
| `isReadOnly` | `bool` | Read-only status based on ACL privileges |

### CalendarEvent

| Property | Type | Description |
|----------|------|-------------|
| `uid` | `String` | Unique identifier (iCalendar UID) |
| `calendarId` | `String` | Parent calendar's UID |
| `href` | `Uri?` | Event resource URL |
| `etag` | `String?` | Entity tag for concurrency |
| `start` | `DateTime` | Start time (UTC) |
| `end` | `DateTime?` | End time (UTC, inclusive for all-day events) |
| `summary` | `String` | Event title |
| `description` | `String?` | Event description |
| `location` | `String?` | Event location |
| `isAllDay` | `bool` | All-day event flag |
| `rawIcalendar` | `String?` | Raw iCalendar data |
| `isReadOnly` | `bool` | Read-only status (inherited from calendar) |
| `rrule` | `String?` | RFC 5545 recurrence rule (e.g., "FREQ=DAILY;COUNT=10") |
| `recurrenceId` | `String?` | RECURRENCE-ID for modified instances |
| `exdate` | `List<String>?` | Exception dates excluded from recurrence |

## Error Handling

```dart
try {
  final calendars = await client.getCalendars();
} on AuthenticationException catch (e) {
  print('Authentication failed: ${e.message}');
} on ForbiddenException catch (e) {
  print('Insufficient permissions: ${e.message}');
} on NotFoundException catch (e) {
  print('Resource not found: ${e.message}');
} on ConflictException catch (e) {
  print('Concurrent modification: ${e.message}');
} on DiscoveryException catch (e) {
  print('Server discovery failed: ${e.message}');
} on CalDavException catch (e) {
  print('CalDAV error: ${e.statusCode} - ${e.message}');
}
```

## Exception Types

| Exception | Status Code | Description |
|-----------|-------------|-------------|
| `CalDavException` | Various | Base exception for CalDAV errors |
| `AuthenticationException` | 401 | Authentication failed |
| `ForbiddenException` | 403 | Insufficient permissions (read-only calendar/event) |
| `NotFoundException` | 404 | Resource not found |
| `ConflictException` | 409, 412 | Concurrent modification conflict (ETag mismatch) |
| `DiscoveryException` | - | CalDAV endpoint discovery failed |
| `ParseException` | - | XML/iCalendar parsing failed |

## Protocol Support

| RFC | Standard | Coverage |
|-----|----------|----------|
| 4791 | CalDAV | Full core support |
| 4918 | WebDAV | PROPFIND, PROPPATCH, MKCALENDAR, REPORT |
| 6764 | CalDAV Discovery | Full implementation |
| 5545 | iCalendar | Parsing and generation (VEVENT, RRULE, EXDATE) |
