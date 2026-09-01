import 'package:meta/meta.dart';

/// メモの解錠状態。[Memo] と現在時刻から導出する値で、保存はしない。
@immutable
sealed class MemoLockState {
  const MemoLockState();

  /// 本文を読んでよいか。
  bool get canRead => this is MemoUnlocked;
}

/// まだ開こうとしていない、あるいは再ロックされた状態。
final class MemoLocked extends MemoLockState {
  const MemoLocked();

  @override
  bool operator ==(Object other) => other is MemoLocked;

  @override
  int get hashCode => (MemoLocked).hashCode;
}

/// 開こうとして待っている状態。
///
/// 待機画面を見ている間しか続かない。離れれば待機そのものが消える。
final class MemoWaiting extends MemoLockState {
  const MemoWaiting({required this.remaining});

  /// 解錠までの残り時間。時間で測れないルールでは null。
  final Duration? remaining;

  @override
  bool operator ==(Object other) =>
      other is MemoWaiting && other.remaining == remaining;

  @override
  int get hashCode => remaining.hashCode;
}

/// 待機は終わったが、問いへの答えを待っている状態。
final class MemoAwaitingAnswers extends MemoLockState {
  const MemoAwaitingAnswers({required this.questions});

  /// 答えてもらう問い。
  final List<String> questions;

  @override
  bool operator ==(Object other) =>
      other is MemoAwaitingAnswers &&
      other.questions.length == questions.length &&
      other.questions.every(questions.contains);

  @override
  int get hashCode => Object.hashAll(questions);
}

/// 解錠されて本文が読める状態。
///
/// 続くのは詳細画面を開いている間だけ。離れれば閉じる。
final class MemoUnlocked extends MemoLockState {
  const MemoUnlocked();

  @override
  bool operator ==(Object other) => other is MemoUnlocked;

  @override
  int get hashCode => (MemoUnlocked).hashCode;
}
