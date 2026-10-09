import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/cubit/stats_state.dart';

export 'package:focusdesk/features/focus/cubit/stats_cubit.dart';

/// Stable statistics for fixtures whose assertions concern another feature.
class FrozenStatsCubit extends Cubit<StatsState> implements StatsCubit {
  FrozenStatsCubit() : super(const StatsState(status: StatsStatus.success));

  @override
  Future<void> refresh() async {}

  @override
  Future<void> reload() => refresh();

  @override
  void reset() {}
}
