import 'xml_namespaces.dart';

/// Builder for PROPFIND request XML bodies
class PropfindBuilder {
  final List<_Property> _properties = [];

  /// Add a DAV property
  PropfindBuilder addDavProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.dav, 'D'));
    return this;
  }

  /// Add a CalDAV property
  PropfindBuilder addCaldavProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.caldav, 'C'));
    return this;
  }

  /// Add an Apple namespace property
  PropfindBuilder addAppleProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.apple, 'A'));
    return this;
  }

  /// Add a CalendarServer namespace property
  PropfindBuilder addCalendarServerProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.calendarServer, 'CS'));
    return this;
  }

  /// Add a custom property with namespace
  PropfindBuilder addProperty(String name, String namespace, String prefix) {
    _properties.add(_Property(name, namespace, prefix));
    return this;
  }

  /// Build the PROPFIND XML body
  String build() {
    final namespaces = <String, String>{};
    final props = StringBuffer();

    // Always include DAV namespace
    namespaces['D'] = XmlNamespaces.dav;

    for (final prop in _properties) {
      namespaces[prop.prefix] = prop.namespace;
      props.writeln('      <${prop.prefix}:${prop.name}/>');
    }

    final nsDeclarations = namespaces.entries
        .map((e) => 'xmlns:${e.key}="${e.value}"')
        .join(' ');

    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind $nsDeclarations>
  <D:prop>
$props  </D:prop>
</D:propfind>''';
  }

  /// Build allprop request
  static String allprop() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:allprop/>
</D:propfind>''';
  }

  /// Build propname request (list available properties)
  static String propname() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:propname/>
</D:propfind>''';
  }

  /// Preset: current-user-principal discovery
  static String currentUserPrincipal() {
    return PropfindBuilder()
        .addDavProperty('current-user-principal')
        .build();
  }

  /// Preset: calendar-home-set discovery
  static String calendarHomeSet() {
    return PropfindBuilder()
        .addCaldavProperty('calendar-home-set')
        .build();
  }

  /// Preset: calendar collection properties
  static String calendarProperties() {
    return PropfindBuilder()
        .addDavProperty('resourcetype')
        .addDavProperty('displayname')
        .addCaldavProperty('calendar-description')
        .addCaldavProperty('calendar-timezone')
        .addCaldavProperty('supported-calendar-component-set')
        .addAppleProperty('calendar-color')
        .addCalendarServerProperty('getctag')
        .build();
  }
}

class _Property {
  final String name;
  final String namespace;
  final String prefix;

  const _Property(this.name, this.namespace, this.prefix);
}
