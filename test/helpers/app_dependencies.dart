import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppDependencies> createTestDependencies() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return AppDependencies(prefs: PrefsService(preferences), hive: HiveService());
}
