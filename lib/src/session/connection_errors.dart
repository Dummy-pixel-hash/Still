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
  return 'Couldn\u2019t connect. Check the details and try again.';
}
