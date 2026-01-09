/// Result of CalDAV endpoint discovery
class DiscoveryResult {
  /// CalDAV endpoint URL (from well-known or base URL)
  final Uri caldavEndpoint;

  /// Current user's principal URL
  final Uri principalUrl;

  /// Calendar home set URL (where calendars are stored)
  final Uri calendarHomeSet;

  /// User's display name (if available)
  final String? displayName;

  const DiscoveryResult({
    required this.caldavEndpoint,
    required this.principalUrl,
    required this.calendarHomeSet,
    this.displayName,
  });

  @override
  String toString() {
    return 'DiscoveryResult('
        'caldavEndpoint: $caldavEndpoint, '
        'principalUrl: $principalUrl, '
        'calendarHomeSet: $calendarHomeSet, '
        'displayName: $displayName)';
  }
}
