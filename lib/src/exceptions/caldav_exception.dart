/// Base exception for CalDAV operations
class CalDavException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  const CalDavException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'CalDavException: $message (HTTP $statusCode)';
    }
    return 'CalDavException: $message';
  }
}

/// Authentication failed (401)
class AuthenticationException extends CalDavException {
  const AuthenticationException([super.message = 'Authentication failed'])
      : super(statusCode: 401);
}

/// Resource not found (404)
class NotFoundException extends CalDavException {
  const NotFoundException([super.message = 'Resource not found'])
      : super(statusCode: 404);
}

/// Conflict during update (409, 412)
class ConflictException extends CalDavException {
  const ConflictException([super.message = 'Resource conflict'])
      : super(statusCode: 409);
}

/// Discovery failed
class DiscoveryException extends CalDavException {
  const DiscoveryException(super.message);
}

/// XML parsing failed
class ParseException extends CalDavException {
  const ParseException(super.message);
}
