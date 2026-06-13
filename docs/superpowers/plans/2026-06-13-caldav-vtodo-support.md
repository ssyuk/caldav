# CalDAV VTODO Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class VTODO (task) support to the `caldav` Dart library so VTODO-only calendars (issue #1) can be read, created, updated, and deleted.

**Architecture:** Introduce an `abstract class CalendarComponent` base holding fields shared by VEVENT and VTODO. Refactor the existing `CalendarEvent` to extend it without changing its public API, and add a new `CalendarTodo` sibling plus `TodoStatus` enum. Mirror the existing parser/service/client layers (`ICalendarParser.parseTodo`, `TodoService`, `CalDavClient.getTodos`/`createTodo`/...) for VTODO. All changes are non-breaking → version bumps to `1.5.0`.

**Tech Stack:** Dart (`sdk: ^3.10.4`), `dio` for HTTP, `xml` for WebDAV parsing, `test` package for unit tests. iCalendar = RFC 5545, CalDAV = RFC 4791.

**Reference spec:** `docs/superpowers/specs/2026-06-13-caldav-vtodo-support-design.md`

---

## File Structure

**New files:**
- `lib/src/event/calendar_component.dart` — abstract base `CalendarComponent` (shared fields + abstract `toIcalendar()`)
- `lib/src/event/todo.dart` — `TodoStatus` enum + `CalendarTodo` model (extends base, `toIcalendar()`, `copyWith`, `isCompleted`)
- `lib/src/event/todo_service.dart` — `TodoService` (list/create/update/delete/findByUid for VTODO)
- `test/todo_test.dart` — all CalendarTodo / parseTodo / TodoService unit tests

**Modified files:**
- `lib/src/event/event.dart` — `CalendarEvent` extends `CalendarComponent` (public API unchanged)
- `lib/src/event/icalendar_parser.dart` — add `parseTodo` / `parseTodos` + `_parseTodoStatus` helper
- `lib/src/caldav_client.dart` — add `getTodos`/`createTodo`/`updateTodo`/`deleteTodo`/`getTodoByUid` + lazy `_todoService`
- `lib/caldav.dart` — export `CalendarComponent`, `CalendarTodo`, `TodoStatus`
- `pubspec.yaml` — version `1.4.2+3` → `1.5.0`
- `CHANGELOG.md`, `README.md`, `example/main.dart` — document VTODO support

**Note on test commands:** `dart test -n "<name>"` filters by test name across all files. `dart analyze` checks for compile/lint errors. Run from repo root `/Users/syuk/dev/dart_caldav_client`.

---

### Task 1: Extract `CalendarComponent` base and make `CalendarEvent` extend it (non-breaking)

**Files:**
- Create: `lib/src/event/calendar_component.dart`
- Modify: `lib/src/event/event.dart:1-69` (imports + class declaration + constructor)
- Test: existing `test/dart_caldav_client_test.dart` acts as the regression guard

- [ ] **Step 1: Run the existing suite to capture the green baseline**

Run: `dart test`
Expected: PASS (all existing CalendarEvent/parser/MultiStatus/Calendar tests green). Record the count.

- [ ] **Step 2: Create the base class**

Create `lib/src/event/calendar_component.dart`:

```dart
/// Base class for iCalendar components shared by VEVENT and VTODO.
///
/// Holds the fields common to events and todos. Concrete subclasses
/// ([CalendarEvent], [CalendarTodo]) add their component-specific fields
/// and implement [toIcalendar].
abstract class CalendarComponent {
  /// Unique identifier (iCalendar UID)
  final String uid;

  /// Calendar ID that this component belongs to
  final String calendarId;

  /// Resource URL (set after creation)
  final Uri? href;

  /// Entity tag for concurrency control
  final String? etag;

  /// Title / summary
  final String summary;

  /// Description
  final String? description;

  /// Location
  final String? location;

  /// Whether this component is read-only (inherited from calendar)
  final bool isReadOnly;

  /// Raw iCalendar data (preserved from server)
  final String? rawIcalendar;

  /// Recurrence rule (RFC 5545 RRULE)
  final String? rrule;

  /// Recurrence ID for modified instances (RFC 5545 RECURRENCE-ID)
  final String? recurrenceId;

  /// Exception dates (RFC 5545 EXDATE)
  final List<String>? exdate;

  const CalendarComponent({
    required this.uid,
    required this.calendarId,
    this.href,
    this.etag,
    required this.summary,
    this.description,
    this.location,
    this.isReadOnly = false,
    this.rawIcalendar,
    this.rrule,
    this.recurrenceId,
    this.exdate,
  });

  /// Serialize this component to a complete VCALENDAR string.
  String toIcalendar();
}
```

- [ ] **Step 3: Make `CalendarEvent` extend the base**

In `lib/src/event/event.dart`, add the import at the top (after the existing `import '../utils/icalendar_utils.dart';`):

```dart
import 'calendar_component.dart';
```

Replace the class declaration line and the entire field block + constructor (lines 4-69, from `class CalendarEvent {` through the end of the constructor `});`) with:

```dart
/// Represents a calendar event (VEVENT)
class CalendarEvent extends CalendarComponent {
  /// Event start time (UTC)
  final DateTime start;

  /// Event end time (UTC)
  final DateTime? end;

  /// Whether this is an all-day event
  final bool isAllDay;

  const CalendarEvent({
    required super.uid,
    required super.calendarId,
    super.href,
    super.etag,
    required this.start,
    this.end,
    required super.summary,
    super.description,
    super.location,
    this.isAllDay = false,
    super.rawIcalendar,
    super.isReadOnly,
    super.rrule,
    super.recurrenceId,
    super.exdate,
  });
```

Leave the rest of the file (`duration` getter, `copyWith`, `toIcalendar`, `toString`, `==`, `hashCode`) unchanged. Add `@override` above the existing `String toIcalendar() {` line.

- [ ] **Step 4: Run analyzer and the existing suite to verify non-breaking**

Run: `dart analyze lib/src/event/event.dart lib/src/event/calendar_component.dart`
Expected: "No issues found!"

Run: `dart test`
Expected: PASS with the SAME count as Step 1 (no test changed; the base extraction is behavior-preserving).

- [ ] **Step 5: Commit**

```bash
git add lib/src/event/calendar_component.dart lib/src/event/event.dart
git commit -m "refactor: extract CalendarComponent base from CalendarEvent

Non-breaking: CalendarEvent's public constructor and fields are
unchanged; shared fields move to a new abstract base that VTODO
will also extend."
```

---

### Task 2: Add `TodoStatus` enum and `CalendarTodo` model

**Files:**
- Create: `lib/src/event/todo.dart`
- Test: `test/todo_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/todo_test.dart`:

```dart
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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/todo_test.dart`
Expected: FAIL — compile error, `CalendarTodo`/`TodoStatus` not defined (not yet exported).

- [ ] **Step 3: Write the model**

Create `lib/src/event/todo.dart`:

```dart
import '../utils/icalendar_utils.dart';
import 'calendar_component.dart';

/// RFC 5545 VTODO status values.
enum TodoStatus { needsAction, inProcess, completed, cancelled }

/// Represents a calendar to-do item (VTODO).
class CalendarTodo extends CalendarComponent {
  /// Start of the task (RFC 5545 DTSTART) — optional.
  final DateTime? dtstart;

  /// Deadline of the task (RFC 5545 DUE) — optional.
  final DateTime? due;

  /// Whether dtstart/due are date-only (all-day) values.
  final bool isAllDay;

  /// Task status (RFC 5545 STATUS). Defaults to [TodoStatus.needsAction].
  final TodoStatus status;

  /// Completion timestamp (RFC 5545 COMPLETED).
  final DateTime? completed;

  /// Completion percentage 0–100 (RFC 5545 PERCENT-COMPLETE).
  final int? percentComplete;

  /// Priority 0–9 (RFC 5545 PRIORITY); 0 means undefined.
  final int? priority;

  const CalendarTodo({
    required super.uid,
    required super.calendarId,
    super.href,
    super.etag,
    required super.summary,
    super.description,
    super.location,
    this.dtstart,
    this.due,
    this.isAllDay = false,
    this.status = TodoStatus.needsAction,
    this.completed,
    this.percentComplete,
    this.priority,
    super.rawIcalendar,
    super.isReadOnly,
    super.rrule,
    super.recurrenceId,
    super.exdate,
  });

  /// Convenience for simple consumers: a todo is "done" if its status is
  /// completed, it has a COMPLETED timestamp, or PERCENT-COMPLETE is 100.
  bool get isCompleted =>
      status == TodoStatus.completed ||
      completed != null ||
      percentComplete == 100;

  /// Create a copy with updated fields.
  CalendarTodo copyWith({
    String? uid,
    String? calendarId,
    Uri? href,
    String? etag,
    String? summary,
    String? description,
    String? location,
    DateTime? dtstart,
    DateTime? due,
    bool? isAllDay,
    TodoStatus? status,
    DateTime? completed,
    int? percentComplete,
    int? priority,
    String? rawIcalendar,
    bool? isReadOnly,
    String? rrule,
    String? recurrenceId,
    List<String>? exdate,
  }) {
    return CalendarTodo(
      uid: uid ?? this.uid,
      calendarId: calendarId ?? this.calendarId,
      href: href ?? this.href,
      etag: etag ?? this.etag,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      dtstart: dtstart ?? this.dtstart,
      due: due ?? this.due,
      isAllDay: isAllDay ?? this.isAllDay,
      status: status ?? this.status,
      completed: completed ?? this.completed,
      percentComplete: percentComplete ?? this.percentComplete,
      priority: priority ?? this.priority,
      rawIcalendar: rawIcalendar ?? this.rawIcalendar,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      rrule: rrule ?? this.rrule,
      recurrenceId: recurrenceId ?? this.recurrenceId,
      exdate: exdate ?? this.exdate,
    );
  }

  @override
  String toIcalendar() {
    // Implemented in Task 3.
    throw UnimplementedError();
  }

  @override
  String toString() =>
      'CalendarTodo(uid: $uid, summary: $summary, due: $due, status: $status)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarTodo && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
```

> Note: `import '../utils/icalendar_utils.dart';` is added now because Task 3 uses it; it is harmless here. The `toIcalendar` body is the only stub and is replaced in Task 3 before any test exercises it.

Add the export so the test can see the types. In `lib/caldav.dart`, after the line `export 'src/event/event.dart' show CalendarEvent;` add:

```dart
export 'src/event/calendar_component.dart' show CalendarComponent;
export 'src/event/todo.dart' show CalendarTodo, TodoStatus;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/todo_test.dart`
Expected: PASS (5 tests in the CalendarTodo group).

Run: `dart analyze lib/src/event/todo.dart`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/src/event/todo.dart lib/caldav.dart test/todo_test.dart
git commit -m "feat: add CalendarTodo model and TodoStatus enum"
```

---

### Task 3: Implement `CalendarTodo.toIcalendar()`

**Files:**
- Modify: `lib/src/event/todo.dart` (replace the `toIcalendar` stub + add `_statusToIcal`)
- Test: `test/todo_test.dart` (add `toIcalendar` group)

- [ ] **Step 1: Write the failing test**

Add this group inside `main()` in `test/todo_test.dart`, after the `CalendarTodo` group's closing `});`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/todo_test.dart -n "toIcalendar"`
Expected: FAIL — `UnimplementedError` thrown by the stub.

- [ ] **Step 3: Implement `toIcalendar`**

In `lib/src/event/todo.dart`, replace the stub:

```dart
  @override
  String toIcalendar() {
    // Implemented in Task 3.
    throw UnimplementedError();
  }
```

with:

```dart
  @override
  String toIcalendar() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');

    buffer.writeln('BEGIN:VTODO');
    buffer.writeln('UID:$uid');
    buffer.writeln('DTSTAMP:${ICalendarUtils.formatUtc(DateTime.now().toUtc())}');

    if (dtstart != null) {
      if (isAllDay) {
        buffer.writeln('DTSTART;VALUE=DATE:${ICalendarUtils.formatDate(dtstart!)}');
      } else {
        buffer.writeln('DTSTART:${ICalendarUtils.formatUtc(dtstart!.toUtc())}');
      }
    }

    // DUE is the deadline instant, not an exclusive end — no +1 day shift.
    if (due != null) {
      if (isAllDay) {
        buffer.writeln('DUE;VALUE=DATE:${ICalendarUtils.formatDate(due!)}');
      } else {
        buffer.writeln('DUE:${ICalendarUtils.formatUtc(due!.toUtc())}');
      }
    }

    buffer.writeln('SUMMARY:${ICalendarUtils.escapeText(summary)}');

    if (description != null && description!.isNotEmpty) {
      buffer.writeln('DESCRIPTION:${ICalendarUtils.escapeText(description!)}');
    }

    if (location != null && location!.isNotEmpty) {
      buffer.writeln('LOCATION:${ICalendarUtils.escapeText(location!)}');
    }

    if (status != TodoStatus.needsAction) {
      buffer.writeln('STATUS:${_statusToIcal(status)}');
    }

    if (completed != null) {
      buffer.writeln('COMPLETED:${ICalendarUtils.formatUtc(completed!.toUtc())}');
    }

    if (percentComplete != null) {
      buffer.writeln('PERCENT-COMPLETE:$percentComplete');
    }

    if (priority != null && priority != 0) {
      buffer.writeln('PRIORITY:$priority');
    }

    if (rrule != null && rrule!.isNotEmpty) {
      buffer.writeln('RRULE:$rrule');
    }

    if (recurrenceId != null && recurrenceId!.isNotEmpty) {
      buffer.writeln('RECURRENCE-ID:$recurrenceId');
    }

    if (exdate != null && exdate!.isNotEmpty) {
      buffer.writeln('EXDATE:${exdate!.join(',')}');
    }

    buffer.writeln('END:VTODO');
    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
  }

  static String _statusToIcal(TodoStatus status) => switch (status) {
        TodoStatus.needsAction => 'NEEDS-ACTION',
        TodoStatus.inProcess => 'IN-PROCESS',
        TodoStatus.completed => 'COMPLETED',
        TodoStatus.cancelled => 'CANCELLED',
      };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/todo_test.dart -n "toIcalendar"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/event/todo.dart test/todo_test.dart
git commit -m "feat: serialize CalendarTodo to VTODO iCalendar"
```

---

### Task 4: Add `ICalendarParser.parseTodo` / `parseTodos`

**Files:**
- Modify: `lib/src/event/icalendar_parser.dart` (add import + two public methods + `_parseTodoStatus`)
- Test: `test/todo_test.dart` (add `parseTodo` / `parseTodos` groups)

- [ ] **Step 1: Write the failing test**

Add these groups inside `main()` in `test/todo_test.dart`. Also add this import at the top of the file (below the existing `import 'package:caldav/caldav.dart';`):

```dart
import 'package:caldav/src/event/icalendar_parser.dart';
```

Groups:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/todo_test.dart -n "parseTodo"`
Expected: FAIL — `parseTodo`/`parseTodos` not defined on `ICalendarParser`.

- [ ] **Step 3: Implement the parser methods**

In `lib/src/event/icalendar_parser.dart`, add the import at the top (below `import 'event.dart';`):

```dart
import 'todo.dart';
```

Add these methods inside the `ICalendarParser` class, right after the existing `parseEvents` method (after its closing `}` near line 128):

```dart
  /// Parse iCalendar string to a single CalendarTodo (first VTODO).
  ///
  /// Unlike [parseEvent], a todo is valid even without DTSTART/DUE — only
  /// UID is required.
  static CalendarTodo? parseTodo(
    String icalendar, {
    required String calendarId,
    Uri? href,
    String? etag,
    bool isReadOnly = false,
  }) {
    final lines = _unfoldLines(icalendar);
    final todoLines = _extractComponent(lines, 'VTODO');

    if (todoLines.isEmpty) return null;

    final properties = _parseProperties(todoLines);

    final uid = properties['UID'];
    if (uid == null) return null;

    final summary = properties['SUMMARY'] ?? 'Untitled';

    final dtstart = _parseDateTime(
      properties['DTSTART'],
      properties['DTSTART;VALUE'],
    );
    final due = _parseDateTime(
      properties['DUE'],
      properties['DUE;VALUE'],
    );

    // All-day if either time field is date-only. Prefer DTSTART, fall back
    // to DUE when DTSTART is absent.
    final isAllDay = properties['DTSTART;VALUE'] == 'DATE' ||
        (properties['DTSTART']?.length == 8) ||
        (properties['DTSTART'] == null &&
            (properties['DUE;VALUE'] == 'DATE' ||
                properties['DUE']?.length == 8));

    final status = _parseTodoStatus(properties['STATUS']);
    final completed = _parseDateTime(properties['COMPLETED'], null);
    final percentComplete = properties['PERCENT-COMPLETE'] != null
        ? int.tryParse(properties['PERCENT-COMPLETE']!)
        : null;
    final priority = properties['PRIORITY'] != null
        ? int.tryParse(properties['PRIORITY']!)
        : null;

    final rrule = properties['RRULE'];
    final recurrenceId = properties['RECURRENCE-ID'];
    final exdate = _parseExdate(todoLines);

    return CalendarTodo(
      uid: uid,
      calendarId: calendarId,
      href: href,
      etag: etag,
      summary: _unescapeIcalText(summary),
      description: properties['DESCRIPTION'] != null
          ? _unescapeIcalText(properties['DESCRIPTION']!)
          : null,
      location: properties['LOCATION'] != null
          ? _unescapeIcalText(properties['LOCATION']!)
          : null,
      dtstart: dtstart,
      due: due,
      isAllDay: isAllDay,
      status: status,
      completed: completed,
      percentComplete: percentComplete,
      priority: priority,
      rawIcalendar: icalendar,
      isReadOnly: isReadOnly,
      rrule: rrule,
      recurrenceId: recurrenceId,
      exdate: exdate,
    );
  }

  /// Parse multiple VTODOs from an iCalendar string.
  static List<CalendarTodo> parseTodos(
    String icalendar, {
    required String calendarId,
    Uri? baseHref,
    bool isReadOnly = false,
  }) {
    final lines = _unfoldLines(icalendar);
    final todos = <CalendarTodo>[];

    var inTodo = false;
    var todoLines = <String>[];

    for (final line in lines) {
      if (line == 'BEGIN:VTODO') {
        inTodo = true;
        todoLines = [];
      } else if (line == 'END:VTODO') {
        inTodo = false;
        final todo = parseTodo(
          'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VTODO\n${todoLines.join('\n')}\nEND:VTODO\nEND:VCALENDAR',
          calendarId: calendarId,
          isReadOnly: isReadOnly,
        );
        if (todo != null) todos.add(todo);
      } else if (inTodo) {
        todoLines.add(line);
      }
    }

    return todos;
  }

  /// Map an iCalendar STATUS value to [TodoStatus].
  static TodoStatus _parseTodoStatus(String? value) {
    switch (value?.toUpperCase()) {
      case 'COMPLETED':
        return TodoStatus.completed;
      case 'IN-PROCESS':
        return TodoStatus.inProcess;
      case 'CANCELLED':
        return TodoStatus.cancelled;
      case 'NEEDS-ACTION':
      default:
        return TodoStatus.needsAction;
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/todo_test.dart -n "parseTodo"`
Expected: PASS (7 tests across the two groups).

Run: `dart analyze lib/src/event/icalendar_parser.dart`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/src/event/icalendar_parser.dart test/todo_test.dart
git commit -m "feat: parse VTODO components into CalendarTodo"
```

---

### Task 5: Round-trip test (parse → serialize → parse)

**Files:**
- Test: `test/todo_test.dart` (add `round-trip` group; no production code change)

- [ ] **Step 1: Write the test**

Add this group inside `main()` in `test/todo_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `dart test test/todo_test.dart -n "round-trip"`
Expected: PASS (2 tests). These exercise already-implemented code, so they should pass immediately; if either fails, it reveals a parse/serialize asymmetry to fix before continuing.

- [ ] **Step 3: Commit**

```bash
git add test/todo_test.dart
git commit -m "test: VTODO parse/serialize round-trip coverage"
```

---

### Task 6: Add `TodoService`

**Files:**
- Create: `lib/src/event/todo_service.dart`
- Test: `test/todo_test.dart` (add `TodoService query body` group — tests only the XML builders, which are extracted as `static` for testability)

- [ ] **Step 1: Write the failing test**

Add this import at the top of `test/todo_test.dart` (below the existing imports):

```dart
import 'package:caldav/src/event/todo_service.dart';
```

Add this group inside `main()`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/todo_test.dart -n "TodoService query body"`
Expected: FAIL — `TodoService` not defined.

- [ ] **Step 3: Implement `TodoService`**

Create `lib/src/event/todo_service.dart`:

```dart
import 'package:dio/dio.dart';

import '../calendar/calendar.dart';
import '../client/dio_webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../utils/icalendar_utils.dart';
import '../webdav/multistatus.dart';
import '../webdav/xml_namespaces.dart';
import 'icalendar_parser.dart';
import 'todo.dart';

/// Service for VTODO (to-do) CRUD operations.
///
/// Mirrors [EventService] but targets VTODO components.
class TodoService {
  final DioWebDavClient _client;

  TodoService(this._client);

  CalendarTodo? _parseTodoFromResponse(
    DavResponse davResponse,
    Calendar calendar,
  ) {
    final calendarData = davResponse.getProperty(
      'calendar-data',
      namespace: XmlNamespaces.caldav,
    );

    if (calendarData == null || calendarData.isEmpty) return null;

    final etag = davResponse.getProperty(
      'getetag',
      namespace: XmlNamespaces.dav,
    );

    return ICalendarParser.parseTodo(
      calendarData,
      calendarId: calendar.uid,
      href: calendar.href.resolve(davResponse.href),
      etag: etag,
      isReadOnly: calendar.isReadOnly,
    );
  }

  List<CalendarTodo> _parseTodosFromResponses(
    List<DavResponse> responses,
    Calendar calendar,
  ) {
    final todos = <CalendarTodo>[];
    for (final davResponse in responses) {
      final todo = _parseTodoFromResponse(davResponse, calendar);
      if (todo != null) todos.add(todo);
    }
    return todos;
  }

  /// List todos in a calendar.
  ///
  /// [start]/[end] apply a server-side time-range filter when both are given;
  /// otherwise all todos are returned (recommended, since many todos have no
  /// DTSTART/DUE and would be missed by a time-range filter).
  Future<List<CalendarTodo>> list(
    Calendar calendar, {
    DateTime? start,
    DateTime? end,
  }) async {
    final body = buildCalendarQueryBody(start: start, end: end);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return [];

      final todos = _parseTodosFromResponses(multiStatus.responses, calendar);
      if (todos.isNotEmpty) return todos;

      // Servers that return hrefs without calendar-data (Naver-style):
      final urlsWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .toList();

      if (urlsWithoutData.isNotEmpty) {
        return _fetchWithMultiget(calendar, urlsWithoutData);
      }

      return [];
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to list todos');
    }
  }

  Future<List<CalendarTodo>> _fetchWithMultiget(
    Calendar calendar,
    List<String> todoPaths,
  ) async {
    if (todoPaths.isEmpty) return [];

    final hrefs = todoPaths
        .map((p) => '<D:href>${ICalendarUtils.escapeXml(p)}</D:href>')
        .join('\n');

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  $hrefs
</C:calendar-multiget>''';

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      return _parseTodosFromResponses(multiStatus.responses, calendar);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to fetch todos');
    }
  }

  /// Create a new todo. Returns the created todo with href and etag.
  Future<CalendarTodo> create(Calendar calendar, CalendarTodo todo) async {
    final todoPath = calendar.href.resolve('${todo.uid}.ics');

    try {
      final response = await _client.put(
        todoPath.toString(),
        body: todo.toIcalendar(),
        ifNoneMatch: '*',
      );

      final etag = response.headers.value('etag');
      return todo.copyWith(href: todoPath, etag: etag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException('Todo already exists');
      }
      throw _mapException(e, 'Failed to create todo');
    }
  }

  /// Update an existing todo (ETag optimistic locking when available).
  Future<CalendarTodo> update(CalendarTodo todo) async {
    if (todo.href == null) {
      throw const CalDavException('Todo href is required for update');
    }

    try {
      final response = await _client.put(
        todo.href.toString(),
        body: todo.toIcalendar(),
        ifMatch: todo.etag,
      );

      final newEtag = response.headers.value('etag');
      return todo.copyWith(etag: newEtag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Todo was modified by another client. Please refresh and try again.');
      }
      throw _mapException(e, 'Failed to update todo');
    }
  }

  /// Delete a todo.
  Future<void> delete(CalendarTodo todo) async {
    if (todo.href == null) {
      throw const CalDavException('Todo href is required for delete');
    }

    try {
      await _client.delete(
        todo.href.toString(),
        ifMatch: todo.etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return; // already deleted
      }
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Todo was modified by another client. Please refresh and try again.');
      }
      throw _mapException(e, 'Failed to delete todo');
    }
  }

  /// Find a todo by UID in a specific calendar. Returns null if not found.
  Future<CalendarTodo?> findByUid(Calendar calendar, String uid) async {
    final body = buildUidQueryBody(uid);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: 1,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return null;

      for (final davResponse in multiStatus.responses) {
        final todo = _parseTodoFromResponse(davResponse, calendar);
        if (todo != null) return todo;
      }

      final urlWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .firstOrNull;

      if (urlWithoutData != null) {
        final todos = await _fetchWithMultiget(calendar, [urlWithoutData]);
        return todos.isNotEmpty ? todos.first : null;
      }

      return null;
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to find todo by UID');
    }
  }

  static CalDavException _mapException(DioException e, String context) {
    return switch (e.response?.statusCode) {
      401 => const AuthenticationException(),
      403 => const ForbiddenException(),
      404 => const NotFoundException(),
      _ => CalDavException(
          '$context: ${e.message}',
          statusCode: e.response?.statusCode,
        ),
    };
  }

  /// Build a calendar-query REPORT body filtering on VTODO.
  ///
  /// Exposed as static for unit testing of the request body.
  static String buildCalendarQueryBody({
    DateTime? start,
    DateTime? end,
  }) {
    final timeRange = (start != null && end != null)
        ? '<C:time-range start="${ICalendarUtils.formatUtc(start)}" end="${ICalendarUtils.formatUtc(end)}"/>'
        : '';

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VTODO">
        $timeRange
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }

  /// Build a calendar-query REPORT body matching a VTODO by UID.
  static String buildUidQueryBody(String uid) {
    final escapedUid = ICalendarUtils.escapeXml(uid);

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VTODO">
        <C:prop-filter name="UID">
          <C:text-match collation="i;octet">$escapedUid</C:text-match>
        </C:prop-filter>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/todo_test.dart -n "TodoService query body"`
Expected: PASS (2 tests).

Run: `dart analyze lib/src/event/todo_service.dart`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/src/event/todo_service.dart test/todo_test.dart
git commit -m "feat: add TodoService for VTODO CRUD"
```

---

### Task 7: Wire `TodoService` into `CalDavClient`

**Files:**
- Modify: `lib/src/caldav_client.dart` (import, `_todoService` field, lazy init, 5 public methods)
- Test: `test/todo_test.dart` (add a guard test that read-only writes throw)

- [ ] **Step 1: Write the failing test**

Add this group inside `main()` in `test/todo_test.dart`:

```dart
  group('CalDavClient todo guards', () {
    test('updateTodo throws ForbiddenException for read-only todo', () {
      final client = CalDavClient(
        baseUrl: 'https://example.com',
        username: 'u',
        password: 'p',
      );
      addTearDown(client.close);

      const todo = CalendarTodo(
        uid: 't', calendarId: 'c', summary: 's', isReadOnly: true,
      );

      expect(
        () => client.updateTodo(todo),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('deleteTodo throws ForbiddenException for read-only todo', () {
      final client = CalDavClient(
        baseUrl: 'https://example.com',
        username: 'u',
        password: 'p',
      );
      addTearDown(client.close);

      const todo = CalendarTodo(
        uid: 't', calendarId: 'c', summary: 's', isReadOnly: true,
      );

      expect(
        () => client.deleteTodo(todo),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });
```

> These tests rely on the read-only guard running BEFORE any network call (matching `updateEvent`/`deleteEvent` at `caldav_client.dart:363-369, 375-381`), so no server is contacted.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/todo_test.dart -n "CalDavClient todo guards"`
Expected: FAIL — `updateTodo`/`deleteTodo` not defined on `CalDavClient`.

- [ ] **Step 3: Implement client methods**

In `lib/src/caldav_client.dart`:

(a) Add imports (after `import 'event/event_service.dart';`):

```dart
import 'event/todo.dart';
import 'event/todo_service.dart';
```

(b) Add a field (after `EventService? _eventService;` near line 40):

```dart
  TodoService? _todoService;
```

(c) In `clearDiscoveryCache()` (near line 251-255), add `_todoService = null;` alongside the existing resets:

```dart
  void clearDiscoveryCache() {
    _discoveryResult = null;
    _calendarService = null;
    _eventService = null;
    _todoService = null;
  }
```

(d) In `_ensureDiscovered()` (near line 476-486), add the lazy init after `_eventService ??= EventService(_webdavClient);`:

```dart
    _todoService ??= TodoService(_webdavClient);
```

(e) Add the public methods. Insert a new section right after the Events section's `getEventByUid` method (after its closing `}` near line 449, before the `// Lifecycle` divider):

```dart
  // ============================================================
  // Todos (VTODO)
  // ============================================================

  /// Get todos from a calendar.
  ///
  /// [start]/[end] apply a server-side time-range filter when both are given;
  /// otherwise all todos are returned.
  Future<List<CalendarTodo>> getTodos(
    Calendar calendar, {
    DateTime? start,
    DateTime? end,
  }) async {
    await _ensureDiscovered();
    return _todoService!.list(calendar, start: start, end: end);
  }

  /// Create a new todo.
  ///
  /// Returns the created todo with href and etag set.
  /// Throws [ForbiddenException] if the calendar is read-only.
  Future<CalendarTodo> createTodo(
    Calendar calendar,
    CalendarTodo todo,
  ) async {
    _ensureWritable(calendar);
    await _ensureDiscovered();
    return _todoService!.create(calendar, todo);
  }

  /// Update an existing todo.
  ///
  /// Uses ETag for optimistic locking if available.
  /// Throws [ConflictException] if the todo was modified by another client.
  /// Throws [ForbiddenException] if the todo is read-only.
  Future<CalendarTodo> updateTodo(CalendarTodo todo) async {
    if (todo.isReadOnly) {
      throw const ForbiddenException('Cannot update a read-only todo');
    }
    await _ensureDiscovered();
    return _todoService!.update(todo);
  }

  /// Delete a todo.
  ///
  /// Throws [ConflictException] if the todo was modified by another client.
  /// Throws [ForbiddenException] if the todo is read-only.
  Future<void> deleteTodo(CalendarTodo todo) async {
    if (todo.isReadOnly) {
      throw const ForbiddenException('Cannot delete a read-only todo');
    }
    await _ensureDiscovered();
    return _todoService!.delete(todo);
  }

  /// Find a todo by UID across all calendars.
  ///
  /// Searches all calendars in parallel. Returns null if no todo is found.
  Future<CalendarTodo?> getTodoByUid(String uid) async {
    await _ensureDiscovered();
    final calendars = await getCalendars();

    final futures = calendars.map((calendar) async {
      final todo = await _todoService!.findByUid(calendar, uid);
      return todo?.copyWith(calendarId: calendar.uid);
    });

    final results = await Future.wait(futures);
    return results.firstWhere(
      (todo) => todo != null,
      orElse: () => null,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/todo_test.dart -n "CalDavClient todo guards"`
Expected: PASS (2 tests).

Run: `dart analyze`
Expected: "No issues found!"

Run: `dart test`
Expected: PASS (all existing + all new todo tests green).

- [ ] **Step 5: Commit**

```bash
git add lib/src/caldav_client.dart test/todo_test.dart
git commit -m "feat: expose getTodos/createTodo/updateTodo/deleteTodo on CalDavClient"
```

---

### Task 8: Docs, version bump, and example

**Files:**
- Modify: `pubspec.yaml` (version line)
- Modify: `CHANGELOG.md` (new entry at top)
- Modify: `README.md` (VTODO section)
- Modify: `example/main.dart` (todo usage)

- [ ] **Step 1: Bump the version**

In `pubspec.yaml`, change:

```yaml
version: 1.4.2+3
```
to:
```yaml
version: 1.5.0
```

- [ ] **Step 2: Add a CHANGELOG entry**

Read the current top of `CHANGELOG.md` first to match its formatting, then prepend a new section. Use this content (adjust heading style to match existing entries):

```markdown
## 1.5.0

### Added
- VTODO (task) support. Calendars containing `VTODO` items can now be read and managed (issue #1).
  - New `CalendarTodo` model and `TodoStatus` enum, sharing a new `CalendarComponent` base with `CalendarEvent`.
  - `ICalendarParser.parseTodo` / `parseTodos` for VTODO parsing (DTSTART/DUE optional; STATUS/COMPLETED/PERCENT-COMPLETE/PRIORITY supported).
  - `CalDavClient.getTodos`, `createTodo`, `updateTodo`, `deleteTodo`, `getTodoByUid`.

### Notes
- Non-breaking: `CalendarEvent`'s public API is unchanged. `CalendarEvent` now extends `CalendarComponent`.
```

- [ ] **Step 3: Add a README usage section**

Read `README.md` to find where event usage is documented, then add a parallel VTODO section. Insert this after the event examples:

```markdown
### Working with todos (VTODO)

```dart
// List todos in a calendar
final todos = await client.getTodos(calendar);
for (final todo in todos) {
  print('${todo.summary} — due ${todo.due} — done: ${todo.isCompleted}');
}

// Create a todo
final created = await client.createTodo(
  calendar,
  CalendarTodo(
    uid: 'task-123',
    calendarId: calendar.uid,
    summary: 'Submit report',
    due: DateTime.utc(2026, 3, 10, 17),
    priority: 1,
  ),
);

// Mark complete and update
await client.updateTodo(
  created.copyWith(status: TodoStatus.completed, percentComplete: 100),
);

// Delete
await client.deleteTodo(created);
```
```

- [ ] **Step 4: Add an example snippet**

Read `example/main.dart`. After the existing loop that prints events, add a parallel todo loop. Insert inside the same per-calendar loop, after the events are printed:

```dart
      final todos = await client.getTodos(cal);
      for (final todo in todos) {
        print('  Todo: ${todo.summary} (done: ${todo.isCompleted})');
      }
```

- [ ] **Step 5: Verify everything still builds and passes**

Run: `dart analyze`
Expected: "No issues found!"

Run: `dart test`
Expected: PASS (full suite).

Run: `dart pub publish --dry-run`
Expected: completes with no errors (warnings about uncommitted files are acceptable until the final commit).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml CHANGELOG.md README.md example/main.dart
git commit -m "docs: document VTODO support, bump to 1.5.0"
```

---

## Post-Implementation

- Open a PR from `feature/vtodo-support` to `main` (the design spec + plan + implementation all live on this branch).
- After publishing `1.5.0` to pub.dev, comment on [issue #1](https://github.com/ssyuk/caldav/issues/1) that VTODO support has shipped.
- The dew integration (spec §10) is a **separate** spec → plan → implementation cycle and is out of scope for this plan.

---

## Self-Review

**1. Spec coverage** (against `2026-06-13-caldav-vtodo-support-design.md`):
- §4.1 model layer → Tasks 1, 2 ✓
- §4.2 parsing (parseTodo/parseTodos, optional DTSTART/DUE, status/completed/percent/priority, all-day DUE no shift) → Task 4 ✓
- §4.3 services & client API (TodoService, getTodos/createTodo/updateTodo/deleteTodo/getTodoByUid, VTODO comp-filter, optional time-range) → Tasks 6, 7 ✓
- §4.4 serialization → Task 3 ✓
- §6 error handling (401/403/404/412, read-only guards) → Tasks 6 (`_mapException`), 7 (guards) ✓
- §7 test strategy (parseTodo cases, round-trip, regression, XML build) → Tasks 1 (regression), 4, 5, 6 ✓
- §8 version/export/docs → Tasks 2 (export), 8 ✓
- §9 backward compatibility (non-breaking) → Task 1 Step 4 verification ✓

**2. Placeholder scan:** The only `throw UnimplementedError()` is the `toIcalendar` stub in Task 2, explicitly replaced in Task 3 before any test exercises it — intentional TDD scaffolding, not a plan gap. No other placeholders.

**3. Type consistency:** `CalendarTodo` fields (`dtstart`, `due`, `isAllDay`, `status`, `completed`, `percentComplete`, `priority`) and `TodoStatus` values (`needsAction`, `inProcess`, `completed`, `cancelled`) are identical across Tasks 2, 3, 4, 6, 7. Method names consistent: `TodoService.list/create/update/delete/findByUid/buildCalendarQueryBody/buildUidQueryBody` ↔ `CalDavClient.getTodos/createTodo/updateTodo/deleteTodo/getTodoByUid`. `_parseTodoStatus` (parser, private) vs `_statusToIcal` (todo.dart, private) are distinct directions and correctly named.
