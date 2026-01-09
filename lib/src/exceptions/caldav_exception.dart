/// Base exception for CalDAV operations
class CaldavException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  const CaldavException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'CaldavException: $message (HTTP $statusCode)';
    }
    return 'CaldavException: $message';
  }
}

/// Authentication failed (401)
class AuthenticationException extends CaldavException {
  const AuthenticationException([super.message = 'Authentication failed'])
      : super(statusCode: 401);
}

/// Resource not found (404)
class NotFoundException extends CaldavException {
  const NotFoundException([super.message = 'Resource not found'])
      : super(statusCode: 404);
}

/// Conflict during update (409, 412)
class ConflictException extends CaldavException {
  const ConflictException([super.message = 'Resource conflict'])
      : super(statusCode: 409);
}

/// Discovery failed
class DiscoveryException extends CaldavException {
  const DiscoveryException(super.message);
}

/// XML parsing failed
class ParseException extends CaldavException {
  const ParseException(super.message);
}
