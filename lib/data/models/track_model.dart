import 'package:equatable/equatable.dart';

class TrackModel extends Equatable {
  TrackModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    this.durationHint,
    List<int> artworkColors = const [],
    this.artworkIcon = 'headphones',
    this.mood = '',
  }) : artworkColors = List<int>.unmodifiable(artworkColors);

  final String id;
  final String title;
  final String artist;
  final String source;
  final Duration? durationHint;
  final List<int> artworkColors;
  final String artworkIcon;
  final String mood;

  bool get isAsset => source.startsWith('assets/');

  TrackModel copyWith({
    String? id,
    String? title,
    String? artist,
    String? source,
    Duration? durationHint,
    bool clearDurationHint = false,
    List<int>? artworkColors,
    String? artworkIcon,
    String? mood,
  }) => TrackModel(
    id: id ?? this.id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    source: source ?? this.source,
    durationHint: clearDurationHint ? null : durationHint ?? this.durationHint,
    artworkColors: artworkColors ?? this.artworkColors,
    artworkIcon: artworkIcon ?? this.artworkIcon,
    mood: mood ?? this.mood,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    artist,
    source,
    durationHint,
    artworkColors,
    artworkIcon,
    mood,
  ];
}
