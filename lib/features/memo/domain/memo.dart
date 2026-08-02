import 'package:flutter/foundation.dart';

/// メモ1件を表すドメインモデル。
@immutable
class Memo {
  const Memo({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Memo.fromJson(Map<String, dynamic> json) => Memo(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  Memo copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
  }) =>
      Memo(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Memo &&
          other.id == id &&
          other.title == title &&
          other.body == body &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, title, body, createdAt, updatedAt);
}
