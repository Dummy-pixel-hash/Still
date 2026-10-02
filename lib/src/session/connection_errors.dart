import '../config/ssh_config.dart';

/// Human-readable connection failures for the terminal overlay.
///
/// Raw exceptions (SocketException text, SSH handshake dumps) are
/// technically accurate but unreadable. This maps the common cases to one
/// calm line each; anything unknown falls back to a short generic message.
/// No dialogs, no banners — the caller renders the string in place.
String friendlyConnectionError(Object error) {
  final raw = '$error'.toLowerCase();
  if (raw.contains('password') && raw.contains('auth') ||
      raw.contains('unable to authenticate') ||
      raw.contains('no more authentication methods') ||
      raw.contains('auth fail')) {
    return 'Wrong password or key for this machine. Check and try again.';
  }
  if (raw.contains('connection refused')) {
    return 'That machine refused SSH. Is the SSH server running on this port?';
  }
  if (raw.contains('timed out') ||
      raw.contains('timeout') ||
      raw.contains('no route to host') ||
      raw.contains('network is unreachable')) {
    return 'Can\u2019t reach that host. Check the address and your network.';
  }
  if (raw.contains('socketexception') && raw.contains('failed host lookup') ||
      raw.contains('name or service not known') ||
      raw.contains('nodename nor servname')) {
    return 'Couldn\u2019t find that hostname. Check the spelling.';
  }
  if (raw.contains('host key') || raw.contains('hostkey')) {
    return 'The host\u2019s identity couldn\u2019t be verified. Not connecting.';
  }
  if (raw.contains('tmux')) {
    return 'Connected, but the remote session wouldn\u2019t start. '
        'Is tmux installed on that machine?';
  }
  if (raw.contains('stateerror') && raw.contains('no previous connection')) {
    return 'Nothing to reattach to yet. Connect first.';
  }
  if (raw.contains('missing authentication') ||
      raw.contains('no identities') ||
      raw.contains('empty private key') ||
      raw.contains('private key material is empty')) {
    return 'Add your password or private key to connect.';
  }
  return 'Couldn\u2019t connect. Check the details and try again.';
}

/// Copy used when no usable secret is available yet. This is not an
/// error — it tells the user where authentication happens. Kept next to
/// [friendlyConnectionError] so both stay in sync.
String authMissingMessage(SshAuthKind authKind) {
  switch (authKind) {
    case SshAuthKind.password:
      return 'Enter your password to connect.';
    case SshAuthKind.privateKey:
      return 'Paste your private key or pick a saved key to connect.';
  }
}

/// Copy used when a session's own details are incomplete (empty host or
/// username, out-of-range port, key auth with no key). Shown instead of
/// dialing a connection that cannot succeed.
String invalidSessionConfigMessage() =>
    'This session is missing something it needs — check the host, username, port, and key.';
