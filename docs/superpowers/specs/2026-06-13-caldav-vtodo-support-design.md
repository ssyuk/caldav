# CalDAV VTODO 지원 — 설계 명세

**날짜:** 2026-06-13
**상태:** 승인됨 (구현 계획 대기)
**범위:** caldav 라이브러리(`dart_caldav_client`)에 VTODO(할 일) 컴포넌트 지원 추가
**관련 이슈:** [ssyuk/caldav#1](https://github.com/ssyuk/caldav/issues/1) — "Events (Tasks) from VTODO Calendars not supported (yet)?"

---

## 1. 배경 / 문제

라이브러리는 현재 `VEVENT`만 처리한다. `VTODO`만 담긴 캘린더(할 일 목록)는 다음 4개 계층 모두가 VEVENT에 고정돼 있어 빈 결과를 반환한다.

| 위치 | 문제 |
|---|---|
| `lib/src/event/icalendar_parser.dart:22, 111-114` | `_extractComponent(lines, 'VEVENT')`, `parseEvents`가 `BEGIN:VEVENT`만 스캔 |
| `lib/src/event/event_service.dart:315, 341` | `calendar-query`/`multiget` 필터가 `<C:comp-filter name="VEVENT">`로 하드코딩 → VTODO 전용 캘린더는 서버가 빈 응답 반환 |
| `lib/src/event/event.dart` | `CalendarEvent.start`가 `required`, VTODO 핵심 속성(`DUE`/`COMPLETED`/`STATUS`/`PERCENT-COMPLETE`/`PRIORITY`) 부재 |
| `lib/src/event/icalendar_parser.dart:40` | `dtstart == null`이면 `null` 반환 → `DTSTART` 없는 VTODO(흔함) 폐기 |

`Calendar` 모델은 이미 `supportsTodos` getter(`lib/src/calendar/calendar.dart:46`)를 갖고 있어 "이 캘린더에 할 일이 있다"는 알 수 있으나, 그 안의 항목을 가져올 수단이 없다.

## 2. 목표 / 비목표

**목표**
- VTODO를 파싱·조회·생성·수정·삭제하는 1급 지원 추가
- `DTSTART`/`DUE`가 없는 VTODO도 허용
- 완료 상태(`STATUS`/`COMPLETED`/`PERCENT-COMPLETE`)를 읽고 쓰기
- 기존 `CalendarEvent` 공개 API를 **비파괴적으로** 유지 (minor 버전 업)
- 소비자 앱(dew)의 `Event(isTodo)` 모델 의미론과 매끄럽게 매핑되는 구조

**비목표 (이번 범위 밖)**
- dew 앱 측 연동 (별도 spec → plan 사이클 — §10 참조)
- VJOURNAL 지원
- RFC 5545 VTODO의 전체 속성(`CREATED`/`LAST-MODIFIED`/`SEQUENCE`/`CATEGORIES`/`GEO`/`URL`/`DURATION` 등) — 실용 표준 세트로 한정
- 혼합 조회(VEVENT+VTODO 동시 반환) — `getEvents`/`getTodos` 타입 분리 유지

## 3. 확정된 결정 사항

브레인스토밍을 통해 확정:
1. **별도 `CalendarTodo` 모델** (통합 모델 아님, breaking change 회피)
2. **공통 베이스 `CalendarComponent`** 도입 (공유 필드 추출, 다형성)
3. **실용 표준 필드 세트** — `status` enum + `isCompleted` 편의 getter 둘 다 제공
4. **`abstract class` 베이스** (sealed 아님) — 파일 분리 자유, 조회 API 타입 분리로 exhaustive switch 불필요
5. 전부 **비파괴적** → 버전 minor bump

## 4. 아키텍처

### 4.1 모델 계층

```dart
// lib/src/event/calendar_component.dart  (신규)
/// VEVENT / VTODO 가 공유하는 iCalendar 컴포넌트 베이스
abstract class CalendarComponent {
  final String uid;
  final String calendarId;
  final Uri? href;
  final String? etag;
  final String summary;
  final String? description;
  final String? location;
  final bool isReadOnly;
  final String? rawIcalendar;
  // 반복 (VEVENT·VTODO 공통)
  final String? rrule;
  final String? recurrenceId;
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

  /// 서브클래스가 BEGIN:VEVENT / BEGIN:VTODO 블록을 포함한
  /// 완전한 VCALENDAR 문자열을 생성
  String toIcalendar();
}
```

```dart
// lib/src/event/event.dart  (리팩토링 — 외부 API 100% 유지)
class CalendarEvent extends CalendarComponent {
  final DateTime start;   // 그대로 required
  final DateTime? end;
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
  // duration, copyWith, toIcalendar, ==, hashCode 등 기존 멤버 유지
}
```

> **비파괴성 검증 포인트:** 외부에서 `CalendarEvent(uid: ..., calendarId: ..., start: ..., summary: ...)` 호출은 그대로 컴파일된다. 모든 필드명·기본값·생성자 시그니처 동일. 베이스 추출은 내부 선언 위치만 바꾼다.

```dart
// lib/src/event/todo.dart  (신규)
enum TodoStatus { needsAction, inProcess, completed, cancelled }

class CalendarTodo extends CalendarComponent {
  final DateTime? dtstart;      // DTSTART (표시 시작) — nullable
  final DateTime? due;          // DUE (마감)          — nullable
  final bool isAllDay;
  final TodoStatus status;      // 기본 needsAction
  final DateTime? completed;    // COMPLETED 타임스탬프
  final int? percentComplete;   // 0–100
  final int? priority;          // RFC 5545 0–9 (0=미지정)

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

  /// 단순 소비자(dew 등)용 편의 getter
  bool get isCompleted =>
      status == TodoStatus.completed ||
      completed != null ||
      percentComplete == 100;

  CalendarTodo copyWith({ /* 모든 필드 */ });

  @override
  String toIcalendar();

  @override
  bool operator ==(Object other) => other is CalendarTodo && other.uid == uid;
  @override
  int get hashCode => uid.hashCode;
}
```

### 4.2 파싱 (`ICalendarParser` 확장)

기존 공유 헬퍼(`_unfoldLines` / `_parseProperties` / `_parseDateTime` / `_unescapeIcalText` / `_parseExdate` / `_extractComponent`)를 재사용하고 VEVENT와 대칭인 메서드를 추가한다.

```dart
static CalendarTodo? parseTodo(
  String icalendar, {
  required String calendarId,
  Uri? href,
  String? etag,
  bool isReadOnly = false,
});

static List<CalendarTodo> parseTodos(
  String icalendar, {
  required String calendarId,
  bool isReadOnly = false,
});
```

VTODO 파싱 규칙 (VEVENT와의 차이점):
- `uid`만 필수 (없으면 `null` 반환). `summary` 기본값 `'Untitled'`
- **`DTSTART`/`DUE`가 둘 다 없어도 유효** — VEVENT의 "DTSTART 없으면 null" 규칙을 적용하지 않음
- `dtstart`/`due`를 각각 nullable로 파싱 (`_parseDateTime` 재사용, `DTSTART;VALUE`·`DUE;VALUE` 파라미터 인식)
- `isAllDay`: 존재하는 시간 필드(우선순위 `DTSTART` → `DUE`)가 `VALUE=DATE`거나 길이 8이면 `true`
- `status`: `STATUS` 값을 `TodoStatus`로 매핑 (`NEEDS-ACTION`→needsAction, `IN-PROCESS`→inProcess, `COMPLETED`→completed, `CANCELLED`→cancelled). 없거나 미인식 → `needsAction`
- `completed`: `COMPLETED` 타임스탬프 (`_parseDateTime`)
- `percentComplete`: `PERCENT-COMPLETE` → `int.tryParse`
- `priority`: `PRIORITY` → `int.tryParse`
- `rrule`/`recurrenceId`/`exdate`: VEVENT와 동일 헬퍼
- **all-day `DUE`는 exclusive 보정을 하지 않는다** — VEVENT의 `DTEND`는 "종료 다음 순간"이라 inclusive 보정했지만, `DUE`는 마감 시각 자체이므로 그대로 둔다 (dew의 `endTime`=마감 의미와 일치)

### 4.3 서비스 & 클라이언트 API

`event_service.dart`와 대칭인 **`lib/src/event/todo_service.dart` 신설**. VTODO comp-filter·todo 파싱·모델이 다르므로 분리가 명료하다. Naver-style multiget 폴백, `_mapException`, ETag 낙관적 잠금은 `EventService`와 동일 패턴을 따른다.

```dart
class TodoService {
  Future<List<CalendarTodo>> list(Calendar calendar, {DateTime? start, DateTime? end});
  Future<CalendarTodo> create(Calendar calendar, CalendarTodo todo);
  Future<CalendarTodo> update(CalendarTodo todo);
  Future<void> delete(CalendarTodo todo);
  Future<CalendarTodo?> findByUid(Calendar calendar, String uid);
}
```

- `calendar-query`/`calendar-multiget` 필터는 `<C:comp-filter name="VTODO">`
- **`time-range`는 옵션**: `start`/`end`를 주면 `<C:time-range>` 필터 적용, 안 주면 전체 조회. 마감/시작 없는 todo가 흔해 time-range로 누락될 수 있으므로 **기본은 전체 조회**를 권장
- `create`: `${todo.uid}.ics`로 PUT, `If-None-Match: *`
- `update`/`delete`: `If-Match: etag` 낙관적 잠금, 412 → `ConflictException`, 404(delete) → 성공 처리

`CalDavClient`에 대칭 공개 메서드 추가:
```dart
Future<List<CalendarTodo>> getTodos(Calendar calendar, {DateTime? start, DateTime? end});
Future<CalendarTodo> createTodo(Calendar calendar, CalendarTodo todo);   // _ensureWritable 가드
Future<CalendarTodo> updateTodo(CalendarTodo todo);                       // isReadOnly → ForbiddenException
Future<void> deleteTodo(CalendarTodo todo);                               // isReadOnly → ForbiddenException
Future<CalendarTodo?> getTodoByUid(String uid);
```
`_ensureDiscovered()`에 `_todoService` lazy 초기화 추가. `getTodosFromCalendars`/`getAllTodos` 대칭 메서드는 YAGNI로 보류.

### 4.4 iCal 직렬화

`CalendarTodo.toIcalendar()`가 `BEGIN:VTODO` 블록을 생성한다. dew의 `ical_export.dart`(`DUE`=마감, `DTSTART`=시작) 문법과 정렬하되, dew가 빠뜨린 완료 상태까지 출력한다.

출력 순서:
- `BEGIN:VCALENDAR` / `VERSION:2.0` / `PRODID:-//dart-caldav-client//EN`
- `BEGIN:VTODO`
- `UID`, `DTSTAMP`(현재 UTC)
- `DTSTART` (있을 때만; all-day는 `;VALUE=DATE`)
- `DUE` (있을 때만; all-day는 `;VALUE=DATE`, exclusive 보정 없음)
- `SUMMARY` / `DESCRIPTION` / `LOCATION` (이스케이프 `ICalendarUtils.escapeText`)
- `STATUS` (`needsAction`이 아닐 때만; enum→대문자 토큰)
- `COMPLETED` (있을 때), `PERCENT-COMPLETE` (있을 때), `PRIORITY` (0/null 아닐 때)
- `RRULE` / `RECURRENCE-ID` / `EXDATE`
- `END:VTODO` / `END:VCALENDAR`

## 5. VTODO ↔ dew Event 매핑 (참고 — 다음 사이클용)

| dew `Event` | `CalendarTodo` | iCal VTODO |
|---|---|---|
| `isTodo` | (타입이 CalendarTodo) | 컴포넌트 = VTODO |
| `endTime` (마감, anchor) | `due` | `DUE` |
| `startTime` (표시 시작) | `dtstart` | `DTSTART` |
| `isCompleted` | `isCompleted` getter | `STATUS:COMPLETED` / `COMPLETED` / `PERCENT-COMPLETE:100` |
| `priority` (low/med/high) | `priority` (0–9) | `PRIORITY` |
| `isAllDay` | `isAllDay` | `;VALUE=DATE` |

> dew의 `Event` 불변식은 todo에서 `endTime`(=DUE) 필수지만 RFC상 `DUE`는 optional이다. `DUE` 없는 VTODO 수신 처리는 dew 측 과제(§10).

## 6. 에러 처리

기존 `EventService`와 동일한 매핑을 재사용한다.
- 401 → `AuthenticationException`
- 403 → `ForbiddenException`
- 404 → `NotFoundException` (delete 시 멱등 처리로 성공)
- 412 → `ConflictException` (ETag 충돌)
- 기타 → `CalDavException(statusCode)`
- read-only 캘린더/항목에 쓰기 시도 → `ForbiddenException` (`_ensureWritable` / `isReadOnly` 가드)

## 7. 테스트 전략

기존 `test/dart_caldav_client_test.dart`의 순수 단위 테스트 패턴(파서·직렬화·모델·XML 문자열 검증, 네트워크 미사용)을 따른다.

- **`parseTodo`**: 완전체 / `DTSTART`만 / `DUE`만 / 둘 다 없음 / 완료상태 3종(`STATUS:COMPLETED`·`COMPLETED` 존재·`PERCENT-COMPLETE:100`) / `PRIORITY` / all-day(`VALUE=DATE`) / `UID` 없음→null / 라인 폴딩 / 이스케이프
- **`parseTodos`**: 다중 VTODO
- **`CalendarTodo.toIcalendar` round-trip**: `parseTodo(todo.toIcalendar())`가 핵심 필드(uid/summary/due/dtstart/status/priority/isAllDay) 보존
- **`isCompleted` getter**: status·completed·percentComplete 각 경로
- **회귀**: 베이스 추출 후 기존 `CalendarEvent` 테스트 전부 통과 (비파괴 검증)
- **`TodoService` XML 빌드**: `calendar-query`/`multiget` 본문에 `comp-filter name="VTODO"`, time-range 유무 분기를 문자열 매칭으로 검증

## 8. 버전·export·문서

- `lib/caldav.dart` export 추가:
  ```dart
  export 'src/event/calendar_component.dart' show CalendarComponent;
  export 'src/event/todo.dart' show CalendarTodo, TodoStatus;
  ```
- `pubspec.yaml` 버전: `1.4.2+3` → **`1.5.0`** (기능 추가·비파괴 → minor)
- `CHANGELOG.md`: VTODO 지원 항목 추가
- `README.md`: VTODO 조회/CRUD 사용 예시 섹션
- `example/main.dart`: todo 조회 예시 추가
- 릴리스 후 이슈 #1에 완료 코멘트

## 9. 하위 호환성

- `CalendarComponent` 베이스는 신규 추가이며, `CalendarEvent`의 공개 생성자·필드·메서드는 변경 없음
- 기존 `getEvents`/`createEvent`/... API 시그니처 불변
- 신규 심볼만 export에 추가 → 기존 import 영향 없음
- 따라서 SemVer minor(`1.5.0`)가 적절

## 10. 후속 작업 — dew 연동 (별도 spec → plan 사이클)

caldav `1.5.0` publish 후 dew에서 진행. caldav 종속 항목과 독립 항목을 구분한다.

**caldav 종속 (1.5.0 연동)**
- `caldav_calendar_source.dart`에 VTODO → `Event(isTodo:true, isCompleted:…)` 매핑 어댑터(`DavTodoExtension`)
- `doCreateEvent`/`doUpdateEvent`의 `start: event.startTime!` 강제 언랩 제거 → todo 분기로 `createTodo`/`updateTodo` 호출
- `fetchEvents`에서 `getTodos` 결과 병합

**caldav 무관 (dew 자체, 선행 가능)**
- `ical_export.dart`에 완료 상태(`STATUS`/`COMPLETED`/`PERCENT-COMPLETE`) 출력 — 현재 round-trip 시 완료 유실 버그
- `ical_import.dart`에 VTODO 파싱 추가 (현재 정규식이 VEVENT만 매칭)
- `DUE` 없는 VTODO 수신 시 처리 (`Event.endTime` required 불변식 완화 또는 가상 마감 정책)
