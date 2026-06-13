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
}
