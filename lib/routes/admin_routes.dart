import 'package:flint_dart/flint_dart.dart';
import 'package:flint_studio/controllers/admin_controller.dart';
import 'package:flint_studio/middlewares/auth_middleware.dart';

class AdminRoutes extends RouteGroup {
  @override
  String get prefix => '';

  @override
  List<Middleware> get middlewares => [AuthMiddleware()];

  @override
  void register(Flint app) {
    final controller = AdminController();

    // Dashboard home page.
    app.get('/', controller.dashboard);
    app.post('/connect', controller.connectDatabase);
    app.post('/connections/update', controller.updateProfile);
    app.post('/connections/delete', controller.deleteProfile);
    app.post('/connections/switch', controller.switchProfile);
    app.post('/import-sql', controller.importSql);

    // Database browser page.
    app.get('/databases', controller.databases);
    app.post('/databases', controller.createDatabase);
    app.post('/databases/:database/drop', controller.dropDatabase);
    app.get('/databases/:database', controller.databaseDetails);
    app.get('/databases/:database/export', controller.exportDatabase);
    app.get('/databases/:database/tables/:table', controller.tableDetails);
    app.get('/databases/:database/tables/:table/export', controller.exportTable);
    app.patch(
      '/databases/:database/tables/:table/rows',
      controller.updateTableRow,
    );
    app.post('/databases/:database/tables/:table/rows/delete', controller.deleteTableRow);
    app.post('/databases/:database/tables/:table/columns/drop', controller.dropTableColumn);
    app.post('/databases/:database/tables/:table/drop', controller.dropTable);
    app.get('/databases/:database/triggers/:trigger', controller.triggerDetails);
    app.post('/databases/:database/tables', controller.createTable);
    app.post('/databases/:database/triggers', controller.createTrigger);
    app.post('/databases/:database/users', controller.createUser);

    // SQL editor page.
    app.get('/query', controller.queryEditor);

    // SQL execution endpoint.
    app.post('/query', controller.runQuery);
  }
}
