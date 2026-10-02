/// Field-level validation for the New Session SSH flow.
///
/// Pure helpers (no widgets) so they are unit-testable. The product flow is:
/// New Session -> SSH configuration/authentication -> Create & Connect ->
/// terminal. Secrets themselves are never validated here beyond
/// presence — format failures surface at connect time via
/// `friendlyConnectionError`.
String? validateSessionHost(String? value) {
  if ((value ?? '').trim().isEmpty) return 'Enter a host — e.g. dev-fra-02.';
  return null;
}

String? validateSessionUsername(String? value) {
  if ((value ?? '').trim().isEmpty) return 'Enter a username.';
  return null;
}

String? validateSessionPort(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) return 'Enter a port (1\u201365535).';
  final port = int.tryParse(trimmed);
  if (port == null || port <= 0 || port >= 65536) {
    return 'Port must be a number 1\u201365535.';
  }
  return null;
}

/// Parses a validated port string. Returns null when invalid — callers
/// must check [validateSessionPort] first.
int? tryParseSessionPort(String value) {
  final port = int.tryParse(value.trim());
  if (port == null || port <= 0 || port >= 65536) return null;
  return port;
}

String? validateSessionPassword(String? value) {
  if ((value ?? '').isEmpty) return 'Enter your password to connect.';
  return null;
}

String? validateSessionPem(String? value) {
  if ((value ?? '').trim().isEmpty) {
    return 'Paste your private key to connect, or pick a saved key.';
  }
  return null;
}
