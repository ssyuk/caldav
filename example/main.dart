import 'package:caldav/caldav.dart';

void main() async {
  CalDavClient? client;

  try {
    // Connect (auto auth + discovery)
    print('Connecting to CalDAV server...');
    client = await CalDavClient.connect(
      baseUrl: 'https://...',
      username: '...',
      password: '...',
    );
    print('Connected!\n');

    // Get calendars
    final calendars = await client.getCalendars();
    print('Found ${calendars.length} calendar(s):');
    for (final cal in calendars) {
      print('  - ${cal.displayName} (uid: ${cal.uid})');
    }

    // Query events for January 2026
    final start = DateTime.utc(2026, 1, 1);
    final end = DateTime.utc(2026, 2, 1);

    print('\n${'=' * 40}');
    print('Events for January 2026');
    print('=' * 40);

    for (final calendar in calendars) {
      print('\n[${calendar.displayName}]');

      final events = await client.getEvents(calendar, start: start, end: end);

      if (events.isEmpty) {
        print('  No events');
        continue;
      }

      events.sort((a, b) => a.start.compareTo(b.start));

      for (final event in events) {
        print('  ${_formatDate(event.start)} - ${event.summary}');
        if (event.location != null) {
          print('    id: ${event.uid}');
        }
      }
    }

    // Example: Find event by UID
    print('\n${'=' * 40}');
    print('Find event by UID example');
    print('=' * 40);

    final event = await client.getEventByUid('example-event-uid');
    if (event != null) {
      print('Found: ${event.summary} in calendar ${event.calendarId}');
    } else {
      print('Event not found');
    }
  } on CalDavException catch (e) {
    print('CalDAV Error: ${e.message}');
  } finally {
    client?.close();
  }
}

String _formatDate(DateTime dt) {
  final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final weekday = weekdays[dt.weekday - 1];

  if (dt.hour == 0 && dt.minute == 0) {
    return '${dt.month}/${dt.day} ($weekday) All day';
  }

  return '${dt.month}/${dt.day} ($weekday) '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
