import 'dart:convert';

import 'package:dio/dio.dart';

/// Basic Authentication interceptor
class BasicAuthInterceptor extends Interceptor {
  final String username;
  final String password;

  BasicAuthInterceptor({
    required this.username,
    required this.password,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    options.headers['Authorization'] = 'Basic $credentials';
    handler.next(options);
  }
}

/// Bearer token authentication interceptor
class BearerAuthInterceptor extends Interceptor {
  String _token;

  BearerAuthInterceptor(this._token);

  /// Update the token
  void updateToken(String newToken) {
    _token = newToken;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Bearer $_token';
    handler.next(options);
  }
}
