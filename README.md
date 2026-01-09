# CalDAV

A comprehensive Dart client library for CalDAV servers (RFC 4791). Provides high-level APIs for calendar and event management with full timezone support.

## Features

- **Server Discovery** (RFC 6764) - Automatic endpoint detection via `.well-known/caldav`
- **Calendar Management** - List, create, update, delete calendars
- **Event Management** - Full CRUD operations with iCalendar (RFC 5545) support
- **Timezone Support** - Timezone-aware datetime handling using `TZDateTime`
- **Multiple Authentication** - Basic Auth and Bearer Token (OAuth)
- **Conflict Detection** - ETag-based optimistic locking

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  caldav: ^1.2.0
```

## Quick Start

```dart
import 'package:caldav/caldav.dart';
import 'package:timezone/data/latest.dart';
import 'package:timezone/timezone.dart';

void main() async {
  // Initialize timezone database (required)
  initializeTimeZones();

  // Connect with auto-discovery
  final client = await CaldavClient.connect(
    baseUrl: 'https://caldav.example.com',
    username: 'user@example.com',
    password: 'password',
  );

  try {
    // Get all calendars
    final calendars = await client.getCalendars();

    // Query events
    final location = getLocation('Asia/Seoul');
    final start = TZDateTime(location, 2024, 1, 1);
    final end = TZDateTime(location, 2024, 2, 1);

    for (final calendar in calendars) {
      final events = await client.getEvents(calendar, start: start, end: end);
      for (final event in events) {
        print('${event.summary} at ${event.start}');
      }
    }
  } finally {
    client.close();
  }
}
```

## Authentication Methods

### Basic Authentication

```dart
final client = await CaldavClient.connect(
  baseUrl: 'https://caldav.example.com',
  username: 'user@example.com',
  password: 'password',
);
```

### Bearer Token (OAuth)

```dart
final client = CaldavClient.withToken(
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
  print('${cal.displayName} (${cal.href})');
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
final updated = await client.updateCalendar(
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
final location = getLocation('Asia/Seoul');
final start = TZDateTime(location, 2024, 1, 1);
final end = TZDateTime(location, 2024, 12, 31);

final events = await client.getEvents(
  calendar,
  start: start,
  end: end,
);
```

### Create Event

```dart
final location = getLocation('Asia/Seoul');
final event = CalendarEvent(
  uid: 'unique-event-id-${DateTime.now().millisecondsSinceEpoch}',
  start: TZDateTime(location, 2024, 6, 15, 14, 0),
  end: TZDateTime(location, 2024, 6, 15, 15, 0),
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
  start: TZDateTime(location, 2024, 6, 15),
  end: TZDateTime(location, 2024, 6, 16),
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

## Error Handling

```dart
try {
  final calendars = await client.getCalendars();
} on AuthenticationException catch (e) {
  print('Authentication failed: ${e.message}');
} on NotFoundException catch (e) {
  print('Resource not found: ${e.message}');
} on ConflictException catch (e) {
  print('Concurrent modification: ${e.message}');
} on CaldavException catch (e) {
  print('CalDAV error: ${e.statusCode} - ${e.message}');
}
```

## Exception Types

| Exception | Status Code | Description |
|-----------|-------------|-------------|
| `AuthenticationException` | 401 | Invalid credentials |
| `NotFoundException` | 404 | Resource not found |
| `ConflictException` | 409, 412 | Concurrent modification |
| `DiscoveryException` | - | Endpoint discovery failed |
| `ParseException` | - | XML/iCalendar parsing error |

## Protocol Support

| RFC | Standard | Coverage |
|-----|----------|----------|
| 4791 | CalDAV | Full core support |
| 4918 | WebDAV | PROPFIND, PROPPATCH, MKCALENDAR, REPORT |
| 6764 | CalDAV Discovery | Full implementation |
| 5545 | iCalendar | Parsing and generation |