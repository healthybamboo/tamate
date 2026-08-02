import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/shared_preferences_provider.dart';
import '../domain/memo.dart';

/// メモの永続化を担う層。
///
/// 保存先を差し替えられるよう抽象に切っておく。
abstract interface class MemoRepository {
  Future<List<Memo>> fetchAll();

  Future<void> saveAll(List<Memo> memos);
}

/// [SharedPreferences] に JSON 配列として保存する実装。
class SharedPreferencesMemoRepository implements MemoRepository {
  SharedPreferencesMemoRepository(this._prefs);

  static const String _key = 'memos';

  final SharedPreferences _prefs;

  @override
  Future<List<Memo>> fetchAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Memo.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> saveAll(List<Memo> memos) async {
    final encoded = jsonEncode(memos.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, encoded);
  }
}

final memoRepositoryProvider = Provider<MemoRepository>(
  (ref) =>
      SharedPreferencesMemoRepository(ref.watch(sharedPreferencesProvider)),
);
