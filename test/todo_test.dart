import 'package:test/test.dart';
import 'package:caldav/caldav.dart';

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
}
