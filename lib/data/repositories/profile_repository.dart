import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';

class ProfileRepository {
  ProfileRepository(this._auth, this._tasks, this._hive, {this.focus});

  final AuthRepository _auth;
  final TaskRepository _tasks;
  final HiveService _hive;
  final FocusRepository? focus;

  Future<UserModel> updateName(String name) async {
    try {
      return await _auth.updateName(name);
    } catch (error) {
      throw mapException(error);
    }
  }

  Future<void> clearAllData() async {
    try {
      // Respect the task repository's queue so an earlier write cannot restore
      // a task after clearing. Accounts, sessions and preferences are untouched.
      await _tasks.clearAll();
      final focusRepository = focus;
      if (focusRepository != null) {
        await focusRepository.clearAll();
      } else {
        await _hive.clear(AppConstants.focusSessionsBox);
      }
    } catch (error) {
      throw mapException(error);
    }
  }
}
