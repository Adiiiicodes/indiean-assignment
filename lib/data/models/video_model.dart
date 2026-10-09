import 'package:equatable/equatable.dart';

class VideoModel extends Equatable {
  VideoModel({
    required this.id,
    required this.title,
    required this.description,
    required this.source,
    List<int> artworkColors = const [],
  }) : artworkColors = List<int>.unmodifiable(artworkColors);

  final String id;
  final String title;
  final String description;
  final String source;
  final List<int> artworkColors;

  @override
  List<Object> get props => [id, title, description, source, artworkColors];
}
