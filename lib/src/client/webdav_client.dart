import 'package:dio/dio.dart';

/// Abstract interface for WebDAV client operations
///
/// This interface allows for different implementations and easier testing
/// through mocking.
abstract class WebDavClient {
  /// PROPFIND - Retrieve properties of a resource
  ///
  /// [path] Resource path
  /// [body] XML body with requested properties
  /// [depth] 0 (resource only), 1 (resource + children), infinity
  Future<Response<String>> propfind(
    String path, {
    required String body,
    int depth = 0,
  });

  /// PROPPATCH - Modify properties of a resource
  Future<Response<String>> proppatch(
    String path, {
    required String body,
  });

  /// MKCALENDAR - Create a new calendar collection (CalDAV)
  Future<Response<String>> mkcalendar(
    String path, {
    String? body,
  });

  /// REPORT - Query calendar data (CalDAV)
  ///
  /// Used for calendar-query and calendar-multiget
  Future<Response<String>> report(
    String path, {
    required String body,
    int depth = 1,
  });

  /// PUT - Create or update a resource
  Future<Response<String>> put(
    String path, {
    required String body,
    String contentType = 'text/calendar; charset=utf-8',
    String? ifMatch,
    String? ifNoneMatch,
  });

  /// DELETE - Remove a resource
  Future<Response<String>> delete(
    String path, {
    String? ifMatch,
  });

  /// GET - Retrieve a resource
  Future<Response<String>> get(String path);

  /// OPTIONS - Check server capabilities
  Future<Response<String>> options(String path);
}
