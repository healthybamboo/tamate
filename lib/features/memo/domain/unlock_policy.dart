/// 解錠まわりの決めごと。詳細は `docs/spec.md` を参照。
abstract final class UnlockPolicy {
  /// 作成時に選べる待機時間。
  static const List<Duration> waitOptions = [
    Duration(minutes: 1),
    Duration(minutes: 10),
    Duration(hours: 1),
    Duration(days: 1),
  ];

  /// 待機時間の既定値。保存データに解錠ルールが無いときもこの長さで読む。
  static const Duration defaultWait = Duration(minutes: 10);

  /// 解錠してから再びロックされるまでの時間。メモごとではなくアプリ共通。
  static const Duration openWindow = Duration(minutes: 5);
}
