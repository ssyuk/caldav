## 1.4.0
- Added HTTPS enforcement by default with `allowInsecure` parameter for development
- Added `getEventsFromCalendars()` for parallel event fetching across multiple calendars
- Added `getAllEvents()` convenience method for fetching all events in parallel
- Optimized `getEventByUid()` to search all calendars in parallel
- Added `WebDavClient` abstract interface for better testability
- Created `ICalendarUtils` utility class to consolidate shared formatting functions
- Refactored `EventService` with helper methods to reduce code duplication
- Added comprehensive unit tests (27 test cases)

## 1.3.0
- Added recurrence support to `CalendarEvent`:
  - `rrule`: RFC 5545 RRULE for recurring events (e.g., "FREQ=DAILY;INTERVAL=1;COUNT=10")
  - `recurrenceId`: RECURRENCE-ID for modified instances of recurring events
  - `exdate`: Exception dates excluded from the recurrence set
- Updated `ICalendarParser` to extract RRULE, RECURRENCE-ID, and EXDATE from iCalendar data
- Updated `CalendarEvent.toIcalendar()` to serialize recurrence fields

## 1.2.2+3
- Added missing changelog

## 1.2.2+2
- Updated README.md dependency reference

## 1.2.2
- Added `isReadOnly` field to `Calendar` and `CalendarEvent` models
- Implemented privilege parsing for read-only calendar detection

## 1.2.1
- Made `uid` field required in `Calendar` class
- Made `calendarId` field required in `CalendarEvent` class
- Removed unused `getEvent` method

## 1.2.0
- Refactored date handling to use `DateTime` instead of `TZDateTime`
- Renamed `CaldavClient` to `CalDavClient` for consistency
- Renamed `CaldavException` to `CalDavException` for consistency
- Removed `timezone` dependency

## 1.1.0
- Added unique identifier (`uid`) field to `Calendar` model

## 1.0.0+2
- Added MIT License
- Simplified caldav dependency specification in README.md

## 1.0.0
- Initial release