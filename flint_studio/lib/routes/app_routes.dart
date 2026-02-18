import 'package:flint_dart/flint_dart.dart';
import 'admin_routes.dart';
import 'studio_auth_routes.dart';

class AppRoutes extends RouteGroup {
  @override
  String get prefix => '';

  @override
  List<Middleware> get middlewares => [];

  @override
  void register(Flint app) {
    app.routes(StudioAuthRoutes());

    // Mount admin routes for FlintStudio.
    app.routes(AdminRoutes());
  }
}
