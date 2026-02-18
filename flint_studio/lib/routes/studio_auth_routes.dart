import 'package:flint_dart/flint_dart.dart';
import 'package:flint_studio/controllers/studio_auth_controller.dart';

class StudioAuthRoutes extends RouteGroup {
  @override
  String get prefix => '';

  @override
  List<Middleware> get middlewares => [];

  @override
  void register(Flint app) {
    final controller = StudioAuthController();

    app.get('/login', controller.loginPage);
    app.post('/login', controller.login);
    app.post('/logout', controller.logout);
  }
}
