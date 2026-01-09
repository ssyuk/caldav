import 'package:xml/xml.dart';

import 'xml_namespaces.dart';

/// Represents a WebDAV multistatus response
class MultiStatus {
  final List<DavResponse> responses;

  const MultiStatus(this.responses);

  /// Parse multistatus XML response
  factory MultiStatus.fromXml(String xmlString) {
    final document = XmlDocument.parse(xmlString);
    final multistatusElement = document.rootElement;

    final responses = multistatusElement
        .findElements('response', namespace: XmlNamespaces.dav)
        .map(DavResponse.fromXml)
        .toList();

    return MultiStatus(responses);
  }

  /// Check if all responses are successful (2xx status)
  bool get isSuccess => responses.every((r) => r.isSuccess);

  /// Get first response (useful for single resource requests)
  DavResponse? get first => responses.isNotEmpty ? responses.first : null;
}

/// Represents a single response in multistatus
class DavResponse {
  final String href;
  final List<PropStat> propStats;

  const DavResponse({
    required this.href,
    required this.propStats,
  });

  factory DavResponse.fromXml(XmlElement element) {
    final href = element
        .findElements('href', namespace: XmlNamespaces.dav)
        .firstOrNull
        ?.innerText ?? '';

    final propStats = element
        .findElements('propstat', namespace: XmlNamespaces.dav)
        .map(PropStat.fromXml)
        .toList();

    return DavResponse(href: href, propStats: propStats);
  }

  /// Check if response is successful
  bool get isSuccess => propStats.any((ps) => ps.isSuccess);

  /// Get successful propstat
  PropStat? get successPropStat => propStats.where((ps) => ps.isSuccess).firstOrNull;

  /// Get property value by local name and namespace
  String? getProperty(String localName, {String? namespace}) {
    for (final propStat in propStats) {
      if (!propStat.isSuccess) continue;
      final value = propStat.getProperty(localName, namespace: namespace);
      if (value != null) return value;
    }
    return null;
  }

  /// Get property element by local name and namespace
  XmlElement? getPropertyElement(String localName, {String? namespace}) {
    for (final propStat in propStats) {
      if (!propStat.isSuccess) continue;
      final element = propStat.getPropertyElement(localName, namespace: namespace);
      if (element != null) return element;
    }
    return null;
  }

  /// Check if resource has specific resourcetype
  bool hasResourceType(String typeName, {String? namespace}) {
    final resourceType = getPropertyElement('resourcetype', namespace: XmlNamespaces.dav);
    if (resourceType == null) return false;

    return resourceType.childElements.any((e) =>
        e.localName == typeName &&
        (namespace == null || e.namespaceUri == namespace));
  }

  /// Check if this is a calendar collection
  bool get isCalendar => hasResourceType('calendar', namespace: XmlNamespaces.caldav);

  /// Check if this is a collection (directory)
  bool get isCollection => hasResourceType('collection', namespace: XmlNamespaces.dav);
}

/// Represents propstat (property + status) in response
class PropStat {
  final XmlElement? propElement;
  final String status;
  final int statusCode;

  const PropStat({
    this.propElement,
    required this.status,
    required this.statusCode,
  });

  factory PropStat.fromXml(XmlElement element) {
    final propElement = element
        .findElements('prop', namespace: XmlNamespaces.dav)
        .firstOrNull;

    final status = element
        .findElements('status', namespace: XmlNamespaces.dav)
        .firstOrNull
        ?.innerText ?? '';

    // Parse status code from "HTTP/1.1 200 OK"
    final statusCode = _parseStatusCode(status);

    return PropStat(
      propElement: propElement,
      status: status,
      statusCode: statusCode,
    );
  }

  /// Check if status is successful (2xx)
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Get property value by local name
  String? getProperty(String localName, {String? namespace}) {
    return getPropertyElement(localName, namespace: namespace)?.innerText;
  }

  /// Get property element by local name
  XmlElement? getPropertyElement(String localName, {String? namespace}) {
    if (propElement == null) return null;

    for (final child in propElement!.childElements) {
      if (child.localName == localName) {
        if (namespace == null || child.namespaceUri == namespace) {
          return child;
        }
      }
    }
    return null;
  }

  static int _parseStatusCode(String status) {
    // "HTTP/1.1 200 OK" -> 200
    final match = RegExp(r'HTTP/\d\.\d\s+(\d+)').firstMatch(status);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }
}
