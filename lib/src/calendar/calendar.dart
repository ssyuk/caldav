/// Represents a CalDAV calendar collection
class Calendar {
  /// Unique identifier (DAV:geteuid)
  final String? id;

  /// Calendar resource URL
  final Uri href;

  /// Display name
  final String displayName;

  /// Calendar description
  final String? description;

  /// Calendar color (Apple extension, format: #RRGGBBAA or #RRGGBB)
  final String? color;

  /// Supported calendar components (VEVENT, VTODO, VJOURNAL)
  final List<String> supportedComponents;

  /// Calendar timezone ID (IANA format)
  final String? timezone;

  /// Collection tag for sync (changes when calendar content changes)
  final String? ctag;

  const Calendar({
    this.id,
    required this.href,
    required this.displayName,
    this.description,
    this.color,
    this.supportedComponents = const ['VEVENT'],
    this.timezone,
    this.ctag,
  });

  /// Check if calendar supports events
  bool get supportsEvents => supportedComponents.contains('VEVENT');

  /// Check if calendar supports todos
  bool get supportsTodos => supportedComponents.contains('VTODO');

  /// Check if calendar supports journal entries
  bool get supportsJournal => supportedComponents.contains('VJOURNAL');

  /// Create a copy with updated fields
  Calendar copyWith({
    String? id,
    Uri? href,
    String? displayName,
    String? description,
    String? color,
    List<String>? supportedComponents,
    String? timezone,
    String? ctag,
  }) {
    return Calendar(
      id: id ?? this.id,
      href: href ?? this.href,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      color: color ?? this.color,
      supportedComponents: supportedComponents ?? this.supportedComponents,
      timezone: timezone ?? this.timezone,
      ctag: ctag ?? this.ctag,
    );
  }

  @override
  String toString() {
    return 'Calendar(displayName: $displayName, href: $href)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Calendar && other.href == href;
  }

  @override
  int get hashCode => href.hashCode;
}
