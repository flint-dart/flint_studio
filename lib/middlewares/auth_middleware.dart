import 'package:flint_dart/flint_dart.dart';

class AuthMiddleware extends Middleware {
  @override
  Handler handle(Handler next) {
    return (Context ctx) async {
      final req = ctx.req;
      final res = ctx.res;
      if (res == null) return null;

      final session = await req.session;
      final isAuthenticated = session?['studio_authenticated'] == true;
      if (isAuthenticated) {
        return await next(ctx);
      }

      final acceptsJson = (req.headers['accept'] ?? '').contains('application/json');
      final isJsonBody = (req.headers['content-type'] ?? '').contains('application/json');
      final wantsJson = acceptsJson || isJsonBody || req.method != 'GET';

      if (wantsJson) {
        return res.status(401).json({
          'ok': false,
          'message': 'Unauthorized. Please login first.',
        });
      }

      final nextPath = Uri.encodeQueryComponent(req.path);
      return res.redirect('/login?next=$nextPath');
    };
  }
}
