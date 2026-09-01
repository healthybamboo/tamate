/// 解錠まわりの決めごと。詳細は `docs/spec.md` を参照。
abstract final class UnlockPolicy {
  /// 作成時に選べる待機時間。
  static const List<Duration> waitOptions = [
    Duration(minutes: 1),
    Duration(minutes: 3),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  /// 待機時間の既定値。保存データに解錠ルールが無いときもこの長さで読む。
  static const Duration defaultWait = Duration(minutes: 3);

  /// 待機時間を伸ばす提案を出し始める開封回数。
  static const int openCountForWaitSuggestion = 3;

  /// 内容の見直しか削除を提案し始める開封回数。
  static const int openCountForReviewSuggestion = 5;

  /// [current] の次に長い待機時間。いちばん長いものなら null。
  ///
  /// 提案から伸ばすときに使う。伸ばす方向にしか動かせないようにしてある。
  static Duration? nextWaitOption(Duration current) {
    for (final option in waitOptions) {
      if (option > current) {
        return option;
      }
    }
    return null;
  }
}
