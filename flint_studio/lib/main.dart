import 'package:flint_dart/flint_dart.dart';
import 'package:flint_studio/routes/app_routes.dart';

Future<void> main() async {
  final app = Flint(
    withDefaultMiddleware: true,
    autoConnectDb: false,
    enableSwaggerDocs: false,
  );

  // Serve static assets from the public folder.
  app.static('/public', 'public');

  // Mount all application routes.
  app.routes(AppRoutes());

  // Start the server.
  await app.listen(port: 4033, hotReload: true);
}
