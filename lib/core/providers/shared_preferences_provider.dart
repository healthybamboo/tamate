import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SharedPreferences] のインスタンス。
///
/// 非同期初期化が必要なため、`main()` で解決した実体を
/// [ProviderScope.overrides] から差し込む。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider は ProviderScope で override すること',
  ),
);
