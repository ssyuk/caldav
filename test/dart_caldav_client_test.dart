import 'package:test/test.dart';
import 'package:caldav/caldav.dart';
import 'package:caldav/src/event/icalendar_parser.dart';
import 'package:caldav/src/webdav/multistatus.dart';

void main() {
  group('ICalendarParser', () {
    group('parseEvent', () {
      test('parses basic event with required fields', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Test//EN
BEGIN:VEVENT
UID:test-uid-123
DTSTART:20240115T100000Z
DTEND:20240115T110000Z
SUMMARY:Test Event
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNotNull);
        expect(event!.uid, equals('test-uid-123'));
        expect(event.summary, equals('Test Event'));
        expect(event.start, equals(DateTime.utc(2024, 1, 15, 10, 0, 0)));
        expect(event.end, equals(DateTime.utc(2024, 1, 15, 11, 0, 0)));
        expect(event.calendarId, equals('calendar-1'));
      });

      test('parses event with description and location', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:test-uid-456
DTSTART:20240115T100000Z
SUMMARY:Meeting
DESCRIPTION:Discuss project updates
LOCATION:Conference Room A
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNotNull);
        expect(event!.description, equals('Discuss project updates'));
        expect(event.location, equals('Conference Room A'));
      });

      test('parses all-day event', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:allday-123
DTSTART;VALUE=DATE:20240115
DTEND;VALUE=DATE:20240116
SUMMARY:All Day Event
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNotNull);
        expect(event!.isAllDay, isTrue);
        expect(event.start.year, equals(2024));
        expect(event.start.month, equals(1));
        expect(event.start.day, equals(15));
      });

      test('parses event with RRULE', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:recurring-123
DTSTART:20240115T100000Z
SUMMARY:Weekly Meeting
RRULE:FREQ=WEEKLY;BYDAY=MO
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNotNull);
        expect(event!.rrule, equals('FREQ=WEEKLY;BYDAY=MO'));
      });

      test('parses event with EXDATE', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:recurring-456
DTSTART:20240115T100000Z
SUMMARY:Weekly Meeting
RRULE:FREQ=WEEKLY;BYDAY=MO
EXDATE:20240122T100000Z,20240129T100000Z
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNotNull);
        expect(event!.exdate, isNotNull);
        expect(event.exdate!.length, equals(2));
      });

      test('parses event with escaped characters', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:escaped-123
DTSTART:20240115T100000Z
SUMMARY:Meeting\\, Important
DESCRIPTION:Line 1\\nLine 2\\nLine 3
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNotNull);
        expect(event!.summary, equals('Meeting, Important'));
        expect(event.description, equals('Line 1\nLine 2\nLine 3'));
      });

      test('returns null for missing UID', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART:20240115T100000Z
SUMMARY:No UID Event
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNull);
      });

      test('returns null for missing DTSTART', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:no-dtstart-123
SUMMARY:No Start Event
END:VEVENT
END:VCALENDAR''';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNull);
      });

      test('handles line folding (RFC 5545)', () {
        // RFC 5545 line folding: CRLF followed by a single whitespace
        const icalendar = 'BEGIN:VCALENDAR\r\n'
            'VERSION:2.0\r\n'
            'BEGIN:VEVENT\r\n'
            'UID:folded-123\r\n'
            'DTSTART:20240115T100000Z\r\n'
            'SUMMARY:This is a very long summary that should be \r\n'
            ' folded across multiple lines according to RFC 5545\r\n'
            'END:VEVENT\r\n'
            'END:VCALENDAR';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(event, isNotNull);
        expect(
          event!.summary,
          equals(
            'This is a very long summary that should be folded across multiple lines according to RFC 5545',
          ),
        );
      });

      test('preserves href and etag when provided', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:test-123
DTSTART:20240115T100000Z
SUMMARY:Test
END:VEVENT
END:VCALENDAR''';

        final href = Uri.parse('https://caldav.example.com/calendars/test.ics');
        const etag = '"abc123"';

        final event = ICalendarParser.parseEvent(
          icalendar,
          calendarId: 'calendar-1',
          href: href,
          etag: etag,
        );

        expect(event, isNotNull);
        expect(event!.href, equals(href));
        expect(event.etag, equals(etag));
      });
    });

    group('parseEvents', () {
      test('parses multiple events', () {
        const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:event-1
DTSTART:20240115T100000Z
SUMMARY:Event 1
END:VEVENT
BEGIN:VEVENT
UID:event-2
DTSTART:20240116T100000Z
SUMMARY:Event 2
END:VEVENT
END:VCALENDAR''';

        final events = ICalendarParser.parseEvents(
          icalendar,
          calendarId: 'calendar-1',
        );

        expect(events.length, equals(2));
        expect(events[0].uid, equals('event-1'));
        expect(events[1].uid, equals('event-2'));
      });
    });
  });

  group('CalendarEvent', () {
    group('toIcalendar', () {
      test('serializes basic event', () {
        final event = CalendarEvent(
          uid: 'test-uid-123',
          calendarId: 'calendar-1',
          start: DateTime.utc(2024, 1, 15, 10, 0, 0),
          end: DateTime.utc(2024, 1, 15, 11, 0, 0),
          summary: 'Test Event',
        );

        final icalendar = event.toIcalendar();

        expect(icalendar, contains('BEGIN:VCALENDAR'));
        expect(icalendar, contains('UID:test-uid-123'));
        expect(icalendar, contains('DTSTART:20240115T100000Z'));
        expect(icalendar, contains('DTEND:20240115T110000Z'));
        expect(icalendar, contains('SUMMARY:Test Event'));
        expect(icalendar, contains('END:VCALENDAR'));
      });

      test('serializes all-day event', () {
        final event = CalendarEvent(
          uid: 'allday-123',
          calendarId: 'calendar-1',
          start: DateTime.utc(2024, 1, 15),
          end: DateTime.utc(2024, 1, 16),
          summary: 'All Day Event',
          isAllDay: true,
        );

        final icalendar = event.toIcalendar();

        expect(icalendar, contains('DTSTART;VALUE=DATE:20240115'));
        expect(icalendar, contains('DTEND;VALUE=DATE:20240116'));
      });

      test('serializes event with description and location', () {
        final event = CalendarEvent(
          uid: 'test-123',
          calendarId: 'calendar-1',
          start: DateTime.utc(2024, 1, 15, 10, 0, 0),
          summary: 'Meeting',
          description: 'Discuss project',
          location: 'Room A',
        );

        final icalendar = event.toIcalendar();

        expect(icalendar, contains('DESCRIPTION:Discuss project'));
        expect(icalendar, contains('LOCATION:Room A'));
      });

      test('escapes special characters', () {
        final event = CalendarEvent(
          uid: 'test-123',
          calendarId: 'calendar-1',
          start: DateTime.utc(2024, 1, 15, 10, 0, 0),
          summary: 'Meeting, Important',
          description: 'Line 1\nLine 2',
        );

        final icalendar = event.toIcalendar();

        expect(icalendar, contains('SUMMARY:Meeting\\, Important'));
        expect(icalendar, contains('DESCRIPTION:Line 1\\nLine 2'));
      });

      test('serializes RRULE', () {
        final event = CalendarEvent(
          uid: 'recurring-123',
          calendarId: 'calendar-1',
          start: DateTime.utc(2024, 1, 15, 10, 0, 0),
          summary: 'Weekly',
          rrule: 'FREQ=WEEKLY;BYDAY=MO',
        );

        final icalendar = event.toIcalendar();

        expect(icalendar, contains('RRULE:FREQ=WEEKLY;BYDAY=MO'));
      });

      test('serializes EXDATE', () {
        final event = CalendarEvent(
          uid: 'recurring-456',
          calendarId: 'calendar-1',
          start: DateTime.utc(2024, 1, 15, 10, 0, 0),
          summary: 'Weekly',
          rrule: 'FREQ=WEEKLY;BYDAY=MO',
          exdate: ['20240122T100000Z', '20240129T100000Z'],
        );

        final icalendar = event.toIcalendar();

        expect(
          icalendar,
          contains('EXDATE:20240122T100000Z,20240129T100000Z'),
        );
      });
    });

    group('copyWith', () {
      test('creates a copy with updated values', () {
        final original = CalendarEvent(
          uid: 'test-123',
          calendarId: 'calendar-1',
          start: DateTime.utc(2024, 1, 15, 10, 0, 0),
          summary: 'Original',
        );

        final modified = original.copyWith(
          summary: 'Modified',
          description: 'New description',
        );

        expect(modified.uid, equals('test-123'));
        expect(modified.summary, equals('Modified'));
        expect(modified.description, equals('New description'));
        expect(original.summary, equals('Original'));
        expect(original.description, isNull);
      });
    });
  });

  group('MultiStatus', () {
    test('parses standard multistatus response', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>/calendars/user/calendar1/</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>My Calendar</D:displayname>
        <D:resourcetype>
          <D:collection/>
          <C:calendar/>
        </D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';

      final multiStatus = MultiStatus.fromXml(xml);

      expect(multiStatus.responses.length, equals(1));
      expect(multiStatus.first!.href, equals('/calendars/user/calendar1/'));
      expect(multiStatus.first!.isCalendar, isTrue);
      expect(multiStatus.first!.isCollection, isTrue);
    });

    test('parses multiple responses', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/calendars/user/</D:href>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/calendars/user/calendar1/</D:href>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';

      final multiStatus = MultiStatus.fromXml(xml);

      expect(multiStatus.responses.length, equals(2));
    });

    test('extracts property values', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>/test/</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>Test Calendar</D:displayname>
        <C:calendar-description>A test calendar</C:calendar-description>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';

      final multiStatus = MultiStatus.fromXml(xml);
      final response = multiStatus.first!;

      expect(
        response.getProperty('displayname', namespace: 'DAV:'),
        equals('Test Calendar'),
      );
      expect(
        response.getProperty(
          'calendar-description',
          namespace: 'urn:ietf:params:xml:ns:caldav',
        ),
        equals('A test calendar'),
      );
    });

    test('handles empty response', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
</D:multistatus>''';

      final multiStatus = MultiStatus.fromXml(xml);

      expect(multiStatus.responses, isEmpty);
      expect(multiStatus.first, isNull);
    });
  });

  group('CalDavClient', () {
    test('throws exception for HTTP URL without allowInsecure', () {
      expect(
        () => CalDavClient(
          baseUrl: 'http://insecure.example.com',
          username: 'user',
          password: 'pass',
        ),
        throwsA(
          isA<CalDavException>().having(
            (e) => e.message,
            'message',
            contains('Insecure connection not allowed'),
          ),
        ),
      );
    });

    test('allows HTTP URL with allowInsecure flag', () {
      final client = CalDavClient(
        baseUrl: 'http://localhost:8080',
        username: 'user',
        password: 'pass',
        allowInsecure: true,
      );

      expect(client, isNotNull);
      client.close();
    });

    test('allows HTTPS URL without allowInsecure', () {
      final client = CalDavClient(
        baseUrl: 'https://secure.example.com',
        username: 'user',
        password: 'pass',
      );

      expect(client, isNotNull);
      client.close();
    });
  });

  group('Calendar', () {
    test('supports component types correctly', () {
      final calendar = Calendar(
        uid: 'cal-1',
        href: Uri.parse('https://example.com/calendars/1/'),
        displayName: 'Test Calendar',
        supportedComponents: ['VEVENT', 'VTODO'],
      );

      expect(calendar.supportsEvents, isTrue);
      expect(calendar.supportsTodos, isTrue);
      expect(calendar.supportsJournal, isFalse);
    });

    test('copyWith creates modified copy', () {
      final original = Calendar(
        uid: 'cal-1',
        href: Uri.parse('https://example.com/calendars/1/'),
        displayName: 'Original',
      );

      final modified = original.copyWith(displayName: 'Modified');

      expect(original.displayName, equals('Original'));
      expect(modified.displayName, equals('Modified'));
      expect(modified.uid, equals(original.uid));
    });
  });
}
