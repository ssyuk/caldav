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