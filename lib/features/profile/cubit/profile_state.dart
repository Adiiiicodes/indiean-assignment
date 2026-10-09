import 'package:equatable/equatable.dart';
import 'package:focusdesk/data/models/user_model.dart';

enum ProfileAction { none, nameUpdated, dataCleared, loggedOut }

class ProfileState extends Equatable {
  const ProfileState({
    this.user,
    this.isBusy = false,
    this.errorMessage,
    this.lastAction = ProfileAction.none,
    this.revision = 0,
  });

  final UserModel? user;
  final bool isBusy;
  final String? errorMessage;
  final ProfileAction lastAction;
  final int revision;

  ProfileState copyWith({
    UserModel? user,
    bool clearUser = false,
    bool? isBusy,
    String? errorMessage,
    bool clearError = false,
    ProfileAction? lastAction,
    int? revision,
  }) => ProfileState(
    user: clearUser ? null : user ?? this.user,
    isBusy: isBusy ?? this.isBusy,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    lastAction: lastAction ?? this.lastAction,
    revision: revision ?? this.revision,
  );

  @override
  List<Object?> get props => [user, isBusy, errorMessage, lastAction, revision];
}
