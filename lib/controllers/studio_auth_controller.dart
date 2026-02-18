import 'package:flint_dart/flint_dart.dart';

class StudioAuthController {
  Future<Response> loginPage(Request req, Response res) async {
    final session = await req.session;
    if (session?['studio_authenticated'] == true) {
      final next = _safeNext(req.query['next']);
      return res.redirect(next);
    }

    return res.view(
      'login',
      data: {
        'errorMessage': (req.query['error'] ?? '').trim(),
        'nextPath': _safeNext(req.query['next']),
      },
    );
  }

  Future<Response> login(Request req, Response res) async {
    final form = await req.form();
    final username = (form['username'] ?? '').trim();
    final password = (form['password'] ?? '').trim();
    final nextPath = _safeNext(form['next'] ?? req.query['next']);

    final expectedUsername = FlintEnv.get('FLINT_STUDIO_USERNAME', 'admin');
    final expectedPassword = FlintEnv.get('FLINT_STUDIO_PASSWORD', 'admin123');

    if (username == expectedUsername && password == expectedPassword) {
      await req.startSession({'studio_authenticated': true, 'studio_user': username});
      return res.redirect(nextPath);
    }

    final err = Uri.encodeQueryComponent('Invalid username or password.');
    final nextQuery = Uri.encodeQueryComponent(nextPath);
    return res.redirect('/login?error=$err&next=$nextQuery');
  }

  Future<Response> logout(Request req, Response res) async {
    await req.destroySession();
    return res.redirect('/login');
  }

  String _safeNext(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty || !value.startsWith('/')) return '/';
    if (value.startsWith('//')) return '/';
    return value;
  }
}
