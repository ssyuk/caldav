# CalDAV

A comprehensive Dart client library for CalDAV servers (RFC 4791). Provides high-level APIs for calendar and event management.

## Features

- **Server Discovery** (RFC 6764) - Automatic endpoint detection via `.well-known/caldav`
- **Calendar Management** - List, create, update, delete calendars with unique identifiers
- **Event Management** - Full CRUD operations with iCalendar (RFC 5545) support
- **Event Search** - Find events by UID across all calendars with server-side filtering
- **Multiple Authentication** - Basic Auth and Bearer Token (OAuth)
- **Conflict Detection** - ETag-based optimistic locking

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  caldav: ^1.3.0
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

## Calendar Operations

### List Calendars

```dart
final calendars = await client.getCalendars();
for (final cal in calendars) {
  print('${cal.displayName} (uid: ${cal.uid})');
  print('  URL: ${cal.href}');
  print('  Color: ${cal.color}');
  print('  Timezone: ${cal.timezone}');
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
  start: DateTime.utc(2024, 6, 15, 14, 0),
  end: DateTime.utc(2024, 6, 15, 15, 0),
  summary: 'Team Meeting',
  description: 'Weekly sync',
  location: 'Conference Room A',
);

final created = await client.createEvent(calendar, event);
```

### Create All-Day Event

```dart
final event = CalendarEvent(
  uid: 'all-day-event-id',
  start: DateTime.utc(2024, 6, 15),
  end: DateTime.utc(2024, 6, 16),
  summary: 'Company Holiday',
  isAllDay: true,
);
```

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

## Data Models

### Calendar

| Property | Type | Description |
|----------|------|-------------|
| `uid` | `String?` | Unique identifier (DAV:geteuid) |
| `href` | `Uri` | Calendar resource URL |
| `displayName` | `String` | Display name |
| `description` | `String?` | Calendar description |
| `color` | `String?` | Color (#RRGGBB or #RRGGBBAA) |
| `timezone` | `String?` | Default timezone (IANA format) |
| `ctag` | `String?` | Collection tag for sync |
| `supportedComponents` | `List<String>` | Supported components (VEVENT, VTODO, etc.) |

### CalendarEvent

| Property | Type | Description |
|----------|------|-------------|
| `uid` | `String` | Unique identifier (iCalendar UID) |
| `calendarId` | `String?` | Parent calendar's UID |
| `href` | `Uri?` | Event resource URL |
| `etag` | `String?` | Entity tag for concurrency |
| `start` | `DateTime` | Start time (UTC) |
| `end` | `DateTime?` | End time (UTC) |
| `summary` | `String` | Event title |
| `description` | `String?` | Event description |
| `location` | `String?` | Event location |
| `isAllDay` | `bool` | All-day event flag |
| `rawIcalendar` | `String?` | Raw iCalendar data |

## Error Handling

```dart
try {
  final calendars = await client.getCalendars();
} on NotFoundException catch (e) {
  print('Resource not found: ${e.message}');
} on ConflictException catch (e) {
  print('Concurrent modification: ${e.message}');
} on CalDavException catch (e) {
  print('CalDAV error: ${e.statusCode} - ${e.message}');
}
```

## Exception Types

| Exception | Status Code | Description |
|-----------|-------------|-------------|
| `CalDavException` | Various | Base exception for CalDAV errors |
| `NotFoundException` | 404 | Resource not found |
| `ConflictException` | 409, 412 | Concurrent modification conflict |

## Protocol Support

| RFC | Standard | Coverage |
|-----|----------|----------|
| 4791 | CalDAV | Full core support |
| 4918 | WebDAV | PROPFIND, PROPPATCH, MKCALENDAR, REPORT |
| 6764 | CalDAV Discovery | Full implementation |
| 5545 | iCalendar | Parsing and generation |
