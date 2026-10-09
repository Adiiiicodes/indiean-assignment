import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/focus/cubit/stats_state.dart';

class StatsCubit extends Cubit<StatsState> {
  StatsCubit(this._repository) : super(const StatsState());

  final FocusRepository _repository;
  Future<void> _reads = Future.value();
  int _generation = 0;

  /// Serialize refreshes so an older result cannot overwrite a newer snapshot.
  Future<void> refresh() {
    final generation = _generation;
    final read = _reads.then<void>((_) async {
      if (!_active(generation)) return;
      emit(state.copyWith(status: StatsStatus.loading, clearError: true));
      try {
        final stats = await _repository.todayStats();
        if (_active(generation)) {
          emit(StatsState(status: StatsStatus.success, stats: stats));
        }
      } catch (error) {
        if (_active(generation)) {
          emit(
            state.copyWith(
              status: StatsStatus.failure,
              errorMessage: mapException(error).message,
            ),
          );
        }
      }
    });
    _reads = read;
    return read;
  }

  Future<void> reload() => refresh();

  void reset() {
    if (isClosed) return;
    _generation++;
    // A fresh authenticated user need not wait for the prior user's read.
    _reads = Future.value();
    emit(const StatsState());
  }

  bool _active(int generation) => !isClosed && generation == _generation;
}
