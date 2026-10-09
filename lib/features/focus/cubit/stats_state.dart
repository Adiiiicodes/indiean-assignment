import 'package:equatable/equatable.dart';
import 'package:focusdesk/data/models/focus_stats.dart';

enum StatsStatus { initial, loading, success, failure }

class StatsState extends Equatable {
  const StatsState({
    this.status = StatsStatus.initial,
    this.stats = const FocusStats(),
    this.errorMessage,
  });

  final StatsStatus status;
  final FocusStats stats;
  final String? errorMessage;

  bool get isLoading => status == StatsStatus.loading;

  StatsState copyWith({
    StatsStatus? status,
    FocusStats? stats,
    String? errorMessage,
    bool clearError = false,
  }) => StatsState(
    status: status ?? this.status,
    stats: stats ?? this.stats,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => [status, stats, errorMessage];
}
