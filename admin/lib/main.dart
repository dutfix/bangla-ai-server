import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await AdminApi.create();
  runApp(AdminApp(api: api));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.api});
  final AdminApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bangla AI Admin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: api.signedIn ? DashboardScreen(api: api) : LoginScreen(api: api),
    );
  }
}
