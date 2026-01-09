/// XML namespaces used in CalDAV/WebDAV protocols
class XmlNamespaces {
  XmlNamespaces._();

  /// WebDAV namespace (RFC 4918)
  static const dav = 'DAV:';

  /// CalDAV namespace (RFC 4791)
  static const caldav = 'urn:ietf:params:xml:ns:caldav';

  /// CardDAV namespace (RFC 6352)
  static const carddav = 'urn:ietf:params:xml:ns:carddav';

  /// Apple iCal namespace (de facto standard)
  static const apple = 'http://apple.com/ns/ical/';

  /// CalendarServer namespace (ctag, sharing)
  static const calendarServer = 'http://calendarserver.org/ns/';
}
