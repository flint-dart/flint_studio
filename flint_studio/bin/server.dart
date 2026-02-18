import 'package:flint_dart/flint_dart.dart';
import 'package:flint_studio/routes/app_routes.dart';

Future<void> main() async {
  // Core Flint server setup for the admin web app.
  final app = Flint(
    withDefaultMiddleware: true,
    autoConnectDb: true,
    enableSwaggerDocs: false,
  );

  // Serve static assets like CSS and JS from /public.
  app.static('/public', 'public');

  // Mount all application routes.
  app.routes(AppRoutes());

  // Start HTTP server.
  await app.listen(port: 3000, hotReload: true);
}
