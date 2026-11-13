import 'package:web/web.dart' as web;

/// Takes ?auth_ticket= / ?auth_error= out of the address bar, so a reload or
/// a shared link does not carry them.
void removeAuthParamsFromAddress() {
  try {
    final u = Uri.parse(web.window.location.href);
    final q = Map<String, String>.from(u.queryParameters)
      ..remove('auth_ticket')
      ..remove('auth_error');
    final query = q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
    final hash = u.hasFragment ? '#${u.fragment}' : '';
    web.window.history.replaceState(null, '', '${u.path}$query$hash');
  } catch (_) {}
}
