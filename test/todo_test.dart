import 'package:test/test.dart';
import 'package:caldav/caldav.dart';
import 'package:caldav/src/event/icalendar_parser.dart';
import 'package:caldav/src/event/todo_service.dart';

void main() {
  group('CalendarTodo', () {
    test('constructs with minimal fields (uid + summary only)', () {
      const todo = CalendarTodo(
        uid: 'todo-1',
        calendarId: 'cal-1',
        summary: 'Buy milk',
      );

      expect(todo.uid, equals('todo-1'));
      expect(todo.summary, equals('Buy milk'));
      expect(todo.dtstart, isNull);
      expect(todo.due, isNull);
      expect(todo.status, equals(TodoStatus.needsAction));
      expect(todo.isCompleted, isFalse);
    });

    group('isCompleted', () {
      test('true when status is completed', () {
        const todo = CalendarTodo(
          uid: 't', calendarId: 'c', summary: 's',
          status: TodoStatus.completed,
        );
        expect(todo.isCompleted, isTrue);
      });

      test('true when COMPLETED timestamp is present', () {
        final todo = CalendarTodo(
          uid: 't', calendarId: 'c', summary: 's',
          completed: DateTime.utc(2026, 1, 1, 9),
        );
        expect(todo.isCompleted, isTrue);
      });

      test('true when percentComplete is 100', () {
        const todo = CalendarTodo(
          uid: 't', calendarId: 'c', summary: 's',
          percentComplete: 100,
        );
        expect(todo.isCompleted, isTrue);
      });

      test('false for needsAction with no completion markers', () {
        const todo = CalendarTodo(
          uid: 't', calendarId: 'c', summary: 's',
          percentComplete: 40,
        );
        expect(todo.isCompleted, isFalse);
      });
    });

    test('copyWith updates fields and preserves others', () {
      const original = CalendarTodo(
        uid: 't', calendarId: 'c', summary: 'Original',
        priority: 5,
      );
      final modified = original.copyWith(
        summary: 'Modified',
        status: TodoStatus.completed,
      );

      expect(modified.uid, equals('t'));
      expect(modified.summary, equals('Modified'));
      expect(modified.status, equals(TodoStatus.completed));
      expect(modified.priority, equals(5));
      expect(original.summary, equals('Original'));
      expect(original.status, equals(TodoStatus.needsAction));
    });

    test('equality is by uid', () {
      const a = CalendarTodo(uid: 't', calendarId: 'c', summary: 'A');
      const b = CalendarTodo(uid: 't', calendarId: 'c', summary: 'B');
      const c = CalendarTodo(uid: 'x', calendarId: 'c', summary: 'A');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('CalendarTodo.toIcalendar', () {
    test('serializes minimal todo', () {
      const todo = CalendarTodo(
        uid: 'todo-1', calendarId: 'c', summary: 'Buy milk',
      );
      final ical = todo.toIcalendar();

      expect(ical, contains('BEGIN:VCALENDAR'));
      expect(ical, contains('BEGIN:VTODO'));
      expect(ical, contains('UID:todo-1'));
      expect(ical, contains('SUMMARY:Buy milk'));
      expect(ical, contains('END:VTODO'));
      // needsAction status is omitted
      expect(ical, isNot(contains('STATUS:')));
      // no time fields when both null
      expect(ical, isNot(contains('DTSTART')));
      expect(ical, isNot(contains('DUE')));
    });

    test('serializes due (timed) without exclusive shift', () {
      final todo = CalendarTodo(
        uid: 't', calendarId: 'c', summary: 'Pay bill',
        due: DateTime.utc(2026, 3, 10, 17, 0, 0),
      );
      final ical = todo.toIcalendar();
      expect(ical, contains('DUE:20260310T170000Z'));
    });

    test('serializes all-day due as VALUE=DATE', () {
      final todo = CalendarTodo(
        uid: 't', calendarId: 'c', summary: 'Report',
        due: DateTime.utc(2026, 3, 10),
        isAllDay: true,
      );
      final ical = todo.toIcalendar();
      expect(ical, contains('DUE;VALUE=DATE:20260310'));
    });

    test('serializes completion markers and priority', () {
      final todo = CalendarTodo(
        uid: 't', calendarId: 'c', summary: 'Done task',
        status: TodoStatus.completed,
        completed: DateTime.utc(2026, 1, 2, 8, 30, 0),
        percentComplete: 100,
        priority: 1,
      );
      final ical = todo.toIcalendar();
      expect(ical, contains('STATUS:COMPLETED'));
      expect(ical, contains('COMPLETED:20260102T083000Z'));
      expect(ical, contains('PERCENT-COMPLETE:100'));
      expect(ical, contains('PRIORITY:1'));
    });

    test('omits priority when 0', () {
      const todo = CalendarTodo(
        uid: 't', calendarId: 'c', summary: 's', priority: 0,
      );
      expect(todo.toIcalendar(), isNot(contains('PRIORITY:')));
    });
  });

  group('ICalendarParser.parseTodo', () {
    CalendarTodo? parse(String ical) =>
        ICalendarParser.parseTodo(ical, calendarId: 'cal-1');

    test('parses a full todo', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:todo-full
DTSTART:20260301T090000Z
DUE:20260310T170000Z
SUMMARY:Write report
DESCRIPTION:Quarterly numbers
LOCATION:Desk
STATUS:IN-PROCESS
PERCENT-COMPLETE:40
PRIORITY:2
END:VTODO
END:VCALENDAR''';

      final todo = parse(ical);
      expect(todo, isNotNull);
      expect(todo!.uid, equals('todo-full'));
      expect(todo.summary, equals('Write report'));
      expect(todo.description, equals('Quarterly numbers'));
      expect(todo.location, equals('Desk'));
      expect(todo.dtstart, equals(DateTime.utc(2026, 3, 1, 9)));
      expect(todo.due, equals(DateTime.utc(2026, 3, 10, 17)));
      expect(todo.status, equals(TodoStatus.inProcess));
      expect(todo.percentComplete, equals(40));
      expect(todo.priority, equals(2));
      expect(todo.calendarId, equals('cal-1'));
    });

    test('parses todo with only DUE (no DTSTART)', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:todo-due-only
DUE:20260310T170000Z
SUMMARY:Deadline only
END:VTODO
END:VCALENDAR''';
      final todo = parse(ical);
      expect(todo, isNotNull);
      expect(todo!.dtstart, isNull);
      expect(todo.due, equals(DateTime.utc(2026, 3, 10, 17)));
    });

    test('parses todo with neither DTSTART nor DUE', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:todo-floating
SUMMARY:Someday
END:VTODO
END:VCALENDAR''';
      final todo = parse(ical);
      expect(todo, isNotNull);
      expect(todo!.dtstart, isNull);
      expect(todo.due, isNull);
      expect(todo.status, equals(TodoStatus.needsAction));
    });

    test('parses all-day DUE (VALUE=DATE)', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:todo-allday
DUE;VALUE=DATE:20260310
SUMMARY:All day deadline
END:VTODO
END:VCALENDAR''';
      final todo = parse(ical);
      expect(todo, isNotNull);
      expect(todo!.isAllDay, isTrue);
      expect(todo.due, equals(DateTime.utc(2026, 3, 10)));
    });

    test('maps STATUS:COMPLETED and COMPLETED timestamp', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:todo-done
SUMMARY:Done
STATUS:COMPLETED
COMPLETED:20260102T083000Z
END:VTODO
END:VCALENDAR''';
      final todo = parse(ical);
      expect(todo, isNotNull);
      expect(todo!.status, equals(TodoStatus.completed));
      expect(todo.completed, equals(DateTime.utc(2026, 1, 2, 8, 30)));
      expect(todo.isCompleted, isTrue);
    });

    test('returns null for missing UID', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
SUMMARY:No uid
END:VTODO
END:VCALENDAR''';
      expect(parse(ical), isNull);
    });
  });

  group('ICalendarParser.parseTodos', () {
    test('parses multiple todos', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:t1
SUMMARY:First
END:VTODO
BEGIN:VTODO
UID:t2
SUMMARY:Second
END:VTODO
END:VCALENDAR''';
      final todos = ICalendarParser.parseTodos(ical, calendarId: 'cal-1');
      expect(todos.length, equals(2));
      expect(todos[0].uid, equals('t1'));
      expect(todos[1].uid, equals('t2'));
    });
  });

  group('TodoService query body', () {
    test('calendar-query filters on VTODO', () {
      final body = TodoService.buildCalendarQueryBody(start: null, end: null);
      expect(body, contains('<C:comp-filter name="VCALENDAR">'));
      expect(body, contains('<C:comp-filter name="VTODO">'));
      expect(body, isNot(contains('VEVENT')));
      expect(body, isNot(contains('<C:time-range')));
    });

    test('calendar-query includes time-range when start and end given', () {
      final body = TodoService.buildCalendarQueryBody(
        start: DateTime.utc(2026, 1, 1),
        end: DateTime.utc(2026, 2, 1),
      );
      expect(body, contains('<C:comp-filter name="VTODO">'));
      expect(body, contains('<C:time-range start="20260101T000000Z" end="20260201T000000Z"/>'));
    });
  });

  group('CalendarTodo round-trip', () {
    test('timed todo survives parse → serialize → parse', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:rt-1
DTSTART:20260301T090000Z
DUE:20260310T170000Z
SUMMARY:Round trip
STATUS:IN-PROCESS
PRIORITY:3
END:VTODO
END:VCALENDAR''';

      final parsed = ICalendarParser.parseTodo(ical, calendarId: 'c');
      expect(parsed, isNotNull);

      final reparsed =
          ICalendarParser.parseTodo(parsed!.toIcalendar(), calendarId: 'c');
      expect(reparsed, isNotNull);
      expect(reparsed!.uid, equals('rt-1'));
      expect(reparsed.summary, equals('Round trip'));
      expect(reparsed.dtstart, equals(parsed.dtstart));
      expect(reparsed.due, equals(parsed.due));
      expect(reparsed.status, equals(TodoStatus.inProcess));
      expect(reparsed.priority, equals(3));
    });

    test('all-day deadline survives round-trip without shifting', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:rt-allday
DUE;VALUE=DATE:20260310
SUMMARY:All day
END:VTODO
END:VCALENDAR''';

      final parsed = ICalendarParser.parseTodo(ical, calendarId: 'c');
      final reparsed =
          ICalendarParser.parseTodo(parsed!.toIcalendar(), calendarId: 'c');
      expect(reparsed!.isAllDay, isTrue);
      // DUE must NOT drift by a day (unlike VEVENT DTEND).
      expect(reparsed.due, equals(DateTime.utc(2026, 3, 10)));
    });
  });
}
