import 'package:dio/dio.dart';

/// WebDAV client wrapper for Dio supporting custom HTTP methods
class DioWebDavClient {
  final Dio dio;

  DioWebDavClient(this.dio);

  /// PROPFIND - Retrieve properties of a resource
  ///
  /// [path] Resource path
  /// [body] XML body with requested properties
  /// [depth] 0 (resource only), 1 (resource + children), infinity
  Future<Response<String>> propfind(
    String path, {
    required String body,
    int depth = 0,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Depth': depth.toString(),
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  /// PROPPATCH - Modify properties of a resource
  Future<Response<String>> proppatch(
    String path, {
    required String body,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'PROPPATCH',
        headers: {
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  /// MKCALENDAR - Create a new calendar collection (CalDAV)
  Future<Response<String>> mkcalendar(
    String path, {
    String? body,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'MKCALENDAR',
        headers: body != null
            ? {'Content-Type': 'application/xml; charset=utf-8'}
            : null,
        responseType: ResponseType.plain,
      ),
    );
  }

  /// REPORT - Query calendar data (CalDAV)
  ///
  /// Used for calendar-query and calendar-multiget
  Future<Response<String>> report(
    String path, {
    required String body,
    int depth = 1,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'REPORT',
        headers: {
          'Depth': depth.toString(),
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  /// PUT - Create or update a resource
  Future<Response<String>> put(
    String path, {
    required String body,
    String contentType = 'text/calendar; charset=utf-8',
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    final headers = <String, String>{
      'Content-Type': contentType,
    };
    if (ifMatch != null) headers['If-Match'] = ifMatch;
    if (ifNoneMatch != null) headers['If-None-Match'] = ifNoneMatch;

    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'PUT',
        headers: headers,
        responseType: ResponseType.plain,
      ),
    );
  }

  /// DELETE - Remove a resource
  Future<Response<String>> delete(
    String path, {
    String? ifMatch,
  }) async {
    final headers = <String, String>{};
    if (ifMatch != null) headers['If-Match'] = ifMatch;

    return dio.request<String>(
      path,
      options: Options(
        method: 'DELETE',
        headers: headers.isNotEmpty ? headers : null,
        responseType: ResponseType.plain,
      ),
    );
  }

  /// GET - Retrieve a resource
  Future<Response<String>> get(String path) async {
    return dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
  }

  /// OPTIONS - Check server capabilities
  Future<Response<String>> options(String path) async {
    return dio.request<String>(
      path,
      options: Options(
        method: 'OPTIONS',
        responseType: ResponseType.plain,
      ),
    );
  }
}
