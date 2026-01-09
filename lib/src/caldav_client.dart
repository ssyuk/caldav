import 'package:dio/dio.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar/calendar.dart';
import 'calendar/calendar_service.dart';
import 'client/dio_webdav_client.dart';
import 'client/interceptors/auth_interceptor.dart';
import 'discovery/discovery_result.dart';
import 'discovery/discovery_service.dart';
import 'event/event.dart';
import 'event/event_service.dart';
import 'exceptions/caldav_exception.dart';
import 'webdav/propfind_builder.dart';

/// CalDAV client for interacting with CalDAV servers
///
/// Example usage:
/// ```dart
/// final client = CaldavClient(
///   baseUrl: 'https://caldav.example.com',
///   username: 'user@example.com',
///   password: 'password',
/// );
///
/// // Check connection
/// if (await client.ping()) {
///   final calendars = await client.getCalendars();
///   print('Found ${calendars.length} calendars');
/// }
///
/// client.close();
/// ```
class CaldavClient {
  final Dio _dio;
  final DioWebDavClient _webdavClient;
  final DiscoveryService _discoveryService;
  final Uri _baseUrl;

  DiscoveryResult? _discoveryResult;
  CalendarService? _calendarService;
  EventService? _eventService;

  CaldavClient._({
    required Dio dio,
    required DioWebDavClient webdavClient,
    required DiscoveryService discoveryService,
    required Uri baseUrl,
  })  : _dio = dio,
        _webdavClient = webdavClient,
        _discoveryService = discoveryService,
        _baseUrl = baseUrl;

  /// Create a CalDAV client with Basic Authentication
  ///
  /// [baseUrl] CalDAV server base URL (e.g., 'https://caldav.example.com')
  /// [username] Username for authentication
  /// [password] Password for authentication
  /// [connectTimeout] Connection timeout (default: 30 seconds)
  /// [receiveTimeout] Receive timeout (default: 30 seconds)
  factory CaldavClient({
    required String baseUrl,
    required String username,
    required String password,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) {
    final uri = Uri.parse(baseUrl);

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      validateStatus: (status) => status != null && status < 500,
    ));

    dio.interceptors.add(BasicAuthInterceptor(
      username: username,
      password: password,
    ));

    final webdavClient = DioWebDavClient(dio);
    final discoveryService = DiscoveryService(webdavClient, dio);

    return CaldavClient._(
      dio: dio,
      webdavClient: webdavClient,
      discoveryService: discoveryService,
      baseUrl: uri,
    );
  }

  /// Create a CalDAV client with Bearer Token Authentication (OAuth)
  ///
  /// [baseUrl] CalDAV server base URL
  /// [token] Bearer token for authentication
  factory CaldavClient.withToken({
    required String baseUrl,
    required String token,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) {
    final uri = Uri.parse(baseUrl);

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      validateStatus: (status) => status != null && status < 500,
    ));

    dio.interceptors.add(BearerAuthInterceptor(token));

    final webdavClient = DioWebDavClient(dio);
    final discoveryService = DiscoveryService(webdavClient, dio);

    return CaldavClient._(
      dio: dio,
      webdavClient: webdavClient,
      discoveryService: discoveryService,
      baseUrl: uri,
    );
  }

  /// Create a CalDAV client with custom Dio instance
  ///
  /// Use this for advanced configuration or custom authentication
  factory CaldavClient.withDio({
    required String baseUrl,
    required Dio dio,
  }) {
    final uri = Uri.parse(baseUrl);
    final webdavClient = DioWebDavClient(dio);
    final discoveryService = DiscoveryService(webdavClient, dio);

    return CaldavClient._(
      dio: dio,
      webdavClient: webdavClient,
      discoveryService: discoveryService,
      baseUrl: uri,
    );
  }

  // ============================================================
  // Connection & Authentication
  // ============================================================

  /// Create and connect a CalDAV client (recommended)
  ///
  /// Creates client, verifies authentication, and discovers endpoints.
  /// Automatically initializes timezone database.
  /// Throws [CaldavException] if authentication fails.
  static Future<CaldavClient> connect({
    required String baseUrl,
    required String username,
    required String password,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) async {
    final client = CaldavClient(
      baseUrl: baseUrl,
      username: username,
      password: password,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    );

    final authenticated = await client.verifyAuth();
    if (!authenticated) {
      client.close();
      throw const CaldavException('Authentication failed', statusCode: 401);
    }

    await client.discover();
    return client;
  }

  /// Verify if credentials are valid
  ///
  /// Returns true if authentication succeeds, false otherwise
  Future<bool> verifyAuth() async {
    try {
      final body = PropfindBuilder.currentUserPrincipal();

      final response = await _webdavClient.propfind(
        _baseUrl.toString(),
        body: body,
        depth: 0,
      );

      // 207 Multi-Status indicates success
      return response.statusCode == 207;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return false;
      }
      rethrow;
    }
  }

  // ============================================================
  // Discovery
  // ============================================================

  /// Discover CalDAV endpoints (well-known, principal, calendar-home)
  ///
  /// This is called automatically when needed, but can be called
  /// manually to pre-fetch endpoint information.
  Future<DiscoveryResult> discover() async {
    _discoveryResult ??= await _discoveryService.discover(_baseUrl);
    return _discoveryResult!;
  }

  /// Get the discovery result (null if not yet discovered)
  DiscoveryResult? get discoveryResult => _discoveryResult;

  /// Clear cached discovery result
  void clearDiscoveryCache() {
    _discoveryResult = null;
    _calendarService = null;
    _eventService = null;
  }

  // ============================================================
  // Calendars
  // ============================================================

  /// Get all calendars for the current user
  Future<List<Calendar>> getCalendars() async {
    await _ensureDiscovered();
    return _calendarService!.list();
  }

  /// Get a specific calendar by URL
  Future<Calendar> getCalendar(Uri calendarUrl) async {
    await _ensureDiscovered();
    return _calendarService!.get(calendarUrl);
  }

  /// Create a new calendar
  ///
  /// [name] Display name for the calendar
  /// [description] Optional description
  /// [color] Optional color in #RRGGBB or #RRGGBBAA format
  /// [timezone] Optional default timezone (IANA format)
  /// [supportedComponents] Components to support (default: ['VEVENT'])
  Future<Calendar> createCalendar(
    String name, {
    String? description,
    String? color,
    String? timezone,
    List<String> supportedComponents = const ['VEVENT'],
  }) async {
    await _ensureDiscovered();
    return _calendarService!.create(
      name,
      description: description,
      color: color,
      timezone: timezone,
      supportedComponents: supportedComponents,
    );
  }

  /// Update calendar properties
  ///
  /// Only provided properties will be updated
  Future<void> updateCalendar(
    Calendar calendar, {
    String? displayName,
    String? description,
    String? color,
  }) async {
    await _ensureDiscovered();
    return _calendarService!.update(
      calendar,
      displayName: displayName,
      description: description,
      color: color,
    );
  }

  /// Delete a calendar
  ///
  /// Warning: This will delete all events in the calendar
  Future<void> deleteCalendar(Calendar calendar) async {
    await _ensureDiscovered();
    return _calendarService!.delete(calendar);
  }

  // ============================================================
  // Events
  // ============================================================

  /// Get events from a calendar
  ///
  /// [calendar] Target calendar
  /// [start] Optional start date filter
  /// [end] Optional end date filter
  Future<List<CalendarEvent>> getEvents(
    Calendar calendar, {
    tz.TZDateTime? start,
    tz.TZDateTime? end,
  }) async {
    await _ensureDiscovered();
    return _eventService!.list(calendar, start: start, end: end);
  }

  /// Get a specific event by URL
  Future<CalendarEvent?> getEvent(Uri eventUrl) async {
    await _ensureDiscovered();
    return _eventService!.get(eventUrl);
  }

  /// Create a new event
  ///
  /// Returns the created event with href and etag set
  Future<CalendarEvent> createEvent(
    Calendar calendar,
    CalendarEvent event,
  ) async {
    await _ensureDiscovered();
    return _eventService!.create(calendar, event);
  }

  /// Update an existing event
  ///
  /// Uses ETag for optimistic locking if available.
  /// Throws [ConflictException] if the event was modified by another client.
  Future<CalendarEvent> updateEvent(CalendarEvent event) async {
    await _ensureDiscovered();
    return _eventService!.update(event);
  }

  /// Delete an event
  ///
  /// Throws [ConflictException] if the event was modified by another client.
  Future<void> deleteEvent(CalendarEvent event) async {
    await _ensureDiscovered();
    return _eventService!.delete(event);
  }

  /// Get multiple events by URLs (efficient batch fetch)
  Future<List<CalendarEvent>> getEventsByUrls(
    Calendar calendar,
    List<Uri> eventUrls,
  ) async {
    await _ensureDiscovered();
    return _eventService!.multiGet(calendar, eventUrls);
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  /// Close the client and release resources
  void close() {
    _dio.close();
  }

  /// Access the underlying Dio instance for advanced operations
  Dio get dio => _dio;

  /// Access the WebDAV client for low-level operations
  DioWebDavClient get webdavClient => _webdavClient;

  // ============================================================
  // Private
  // ============================================================

  Future<void> _ensureDiscovered() async {
    if (_discoveryResult == null) {
      await discover();
    }
    // Initialize services if not yet created
    _calendarService ??= CalendarService(
      _webdavClient,
      _discoveryResult!.calendarHomeSet,
    );
    _eventService ??= EventService(_webdavClient);
  }
}
