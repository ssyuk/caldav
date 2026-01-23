import 'package:dio/dio.dart';

import 'webdav_client.dart';

/// WebDAV client implementation using Dio HTTP library
///
/// Supports custom HTTP methods required by WebDAV/CalDAV protocol.
class DioWebDavClient implements WebDavClient {
  final Dio dio;

  DioWebDavClient(this.dio);

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
  Future<Response<String>> get(String path) async {
    return dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
  }

  @override
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
