import 'package:equatable/equatable.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';

enum SuggestedStatus { initial, loading, success, failure }

class SuggestedState extends Equatable {
  SuggestedState({
    this.status = SuggestedStatus.initial,
    List<SuggestedTaskModel> items = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.errorMessage,
    Set<int> importedIds = const {},
    Set<int> importingIds = const {},
  }) : items = List<SuggestedTaskModel>.unmodifiable(items),
       importedIds = Set<int>.unmodifiable(importedIds),
       importingIds = Set<int>.unmodifiable(importingIds);

  final SuggestedStatus status;
  final List<SuggestedTaskModel> items;
  final bool hasMore;
  final bool isLoadingMore;
  final String? errorMessage;
  final Set<int> importedIds;
  final Set<int> importingIds;

  SuggestedState copyWith({
    SuggestedStatus? status,
    List<SuggestedTaskModel>? items,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    Set<int>? importedIds,
    Set<int>? importingIds,
  }) => SuggestedState(
    status: status ?? this.status,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    importedIds: importedIds ?? this.importedIds,
    importingIds: importingIds ?? this.importingIds,
  );

  @override
  List<Object?> get props => [
    status,
    items,
    hasMore,
    isLoadingMore,
    errorMessage,
    importedIds,
    importingIds,
  ];
}
