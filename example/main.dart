import 'package:caldav/caldav.dart';
import 'package:timezone/data/latest.dart';
import 'package:timezone/timezone.dart';

void main() async {
  // Initialize timezone database
  initializeTimeZones();

  CaldavClient? client;

  try {
    // Connect (auto auth + discovery)
    print('Connecting to Naver Calendar...');
    client = await CaldavClient.connect(
      baseUrl: 'https://...',
      username: '...',
      password: '...',
    );
    print('Connected!\n');

    // Get calendars
    final calendars = await client.getCalendars();
    print('Found ${calendars.length} calendar(s):');
    for (final cal in calendars) {
      print('  - ${cal.displayName}');
    }

    // Query events for January 2026
    final location = getLocation('Asia/Seoul');
    final start = TZDateTime(location, 2026, 1, 1);
    final end = TZDateTime(location, 2026, 2, 1);

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
          print('    Location: ${event.location}');
        }
      }
    }
  } on CaldavException catch (e) {
    print('CalDAV Error: ${e.message}');
  } finally {
    client?.close();
  }
}

String _formatDate(TZDateTime dt) {
  final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final weekday = weekdays[dt.weekday - 1];

  if (dt.hour == 0 && dt.minute == 0) {
    return '${dt.month}/${dt.day} ($weekday) All day';
  }

  return '${dt.month}/${dt.day} ($weekday) '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
