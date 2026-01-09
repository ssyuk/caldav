import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../client/dio_webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../webdav/multistatus.dart';
import '../webdav/propfind_builder.dart';
import '../webdav/xml_namespaces.dart';
import 'discovery_result.dart';

/// Service for discovering CalDAV endpoints (RFC 6764)
class DiscoveryService {
  final DioWebDavClient _client;
  final Dio _dio;

  DiscoveryService(this._client, this._dio);

  /// Discover CalDAV endpoints from base URL
  ///
  /// Discovery flow:
  /// 1. Try /.well-known/caldav for redirect
  /// 2. PROPFIND for current-user-principal
  /// 3. PROPFIND for calendar-home-set
  Future<DiscoveryResult> discover(Uri baseUrl) async {
    // Step 1: Well-known discovery
    final caldavEndpoint = await _discoverWellKnown(baseUrl);

    // Step 2: Current user principal
    final principalUrl = await _discoverPrincipal(caldavEndpoint);

    // Step 3: Calendar home set
    final (calendarHome, displayName) = await _discoverCalendarHome(principalUrl);

    return DiscoveryResult(
      caldavEndpoint: caldavEndpoint,
      principalUrl: principalUrl,
      calendarHomeSet: calendarHome,
      displayName: displayName,
    );
  }

  /// Step 1: Try well-known URL for CalDAV endpoint
  Future<Uri> _discoverWellKnown(Uri baseUrl) async {
    final wellKnownUrl = baseUrl.resolve('/.well-known/caldav');

    try {
      final response = await _dio.get<String>(
        wellKnownUrl.toString(),
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      // Handle redirect
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers.value('location');
        if (location != null) {
          return baseUrl.resolve(location);
        }
      }

      // 200 OK - well-known URL is the endpoint
      return wellKnownUrl;
    } on DioException catch (e) {
      // 404 - well-known not supported, use base URL
      if (e.response?.statusCode == 404) {
        return baseUrl;
      }
      // 401 - authentication required at base URL
      if (e.response?.statusCode == 401) {
        return baseUrl;
      }
      rethrow;
    }
  }

  /// Step 2: Discover current user's principal URL
  Future<Uri> _discoverPrincipal(Uri endpoint) async {
    final body = PropfindBuilder.currentUserPrincipal();

    try {
      final response = await _client.propfind(
        endpoint.toString(),
        body: body,
        depth: 0,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final davResponse = multiStatus.first;

      if (davResponse == null) {
        throw const DiscoveryException('No response from server');
      }

      // Get current-user-principal href
      final principalElement = davResponse.getPropertyElement(
        'current-user-principal',
        namespace: XmlNamespaces.dav,
      );

      final href = principalElement
          ?.findElements('href', namespace: XmlNamespaces.dav)
          .firstOrNull
          ?.innerText;

      if (href == null || href.isEmpty) {
        throw const DiscoveryException('current-user-principal not found');
      }

      return endpoint.resolve(href);
    } on DioException catch (e) {
      throw DiscoveryException(
        'Failed to discover principal: ${e.message}',
      );
    }
  }

  /// Step 3: Discover calendar home set from principal
  Future<(Uri, String?)> _discoverCalendarHome(Uri principalUrl) async {
    final body = PropfindBuilder()
        .addCalDavProperty('calendar-home-set')
        .addDavProperty('displayname')
        .build();

    try {
      final response = await _client.propfind(
        principalUrl.toString(),
        body: body,
        depth: 0,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final davResponse = multiStatus.first;

      if (davResponse == null) {
        throw const DiscoveryException('No response from server');
      }

      // Get calendar-home-set href
      final homeSetElement = davResponse.getPropertyElement(
        'calendar-home-set',
        namespace: XmlNamespaces.caldav,
      );

      final href = homeSetElement
          ?.findElements('href', namespace: XmlNamespaces.dav)
          .firstOrNull
          ?.innerText;

      if (href == null || href.isEmpty) {
        throw const DiscoveryException('calendar-home-set not found');
      }

      // Get display name (optional)
      final displayName = davResponse.getProperty(
        'displayname',
        namespace: XmlNamespaces.dav,
      );

      return (principalUrl.resolve(href), displayName);
    } on DioException catch (e) {
      throw DiscoveryException(
        'Failed to discover calendar home: ${e.message}',
      );
    }
  }
}
