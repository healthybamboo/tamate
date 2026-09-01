import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock/clock.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/memo_list_notifier.dart';
import '../domain/memo.dart';
import '../domain/memo_lock_state.dart';
import '../domain/unlock_policy.dart';
import 'duration_format.dart';
import 'memo_display.dart';

/// メモを開く画面。
///
/// ロック中・待機中・コード入力待ち・解錠中のどれを見せるかは
/// [Memo.lockStateAt] の結果で決まる。解錠するまで本文はウィジェットツリーにも載せない。
class MemoDetailPage extends ConsumerStatefulWidget {
  const MemoDetailPage({super.key, required this.memoId});

  final String memoId;

  @override
  ConsumerState<MemoDetailPage> createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends ConsumerState<MemoDetailPage> {
  /// 解錠時刻を記録済みの待機。待ち直したらまた記録する。
  DateTime? _settledWait;

  /// 提案を「あとで」で閉じたか。閉じるのはこの表示の間だけ。
  bool _suggestionDismissed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final memo = ref.watch(memoProvider(widget.memoId));

    if (memo == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.memoNotFound)),
      );
    }

    // ロック中は時間で表示が変わらないので、秒ごとの更新もいらない。
    final clockNow = ref.read(clockProvider).now();
    final now =
        memo.lockStateAt(clockNow) is MemoLocked ? clockNow : watchNow(ref);
    final lockState = memo.lockStateAt(now);

    if (lockState.canRead && memo.unlockedAt == null) {
      _settleUnlock(memo.waitStartedAt);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(memoDisplayTitle(l10n, memo)),
        actions: [
          if (lockState.canRead)
            IconButton(
              onPressed: () => context.push(AppRoutes.memoEdit(widget.memoId)),
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.actionEdit,
            ),
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.actionDelete,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: switch (lockState) {
                MemoLocked() =>
                  _LockedView(memo: memo, onOpen: () => _open(memo)),
                MemoWaiting(:final remaining, :final unlockAt) => _WaitingView(
                    remaining: remaining,
                    unlockAt: unlockAt,
                    now: now,
                    onStopWaiting: _stopWaiting,
                  ),
                MemoUnlocked(:final remaining) => _UnlockedView(
                    memo: memo,
                    remaining: remaining,
                    showSuggestion: !_suggestionDismissed,
                    onExtendWait: _extendWait,
                    onReview: () =>
                        context.push(AppRoutes.memoEdit(widget.memoId)),
                    onDelete: _delete,
                    onDismissSuggestion: () =>
                        setState(() => _suggestionDismissed = true),
                  ),
              },
            ),
            _OpenHistory(memo: memo, now: now),
          ],
        ),
      ),
    );
  }

  /// 解錠を検知した時刻の記録。ビルド中に書き換えないよう1フレーム待つ。
  void _settleUnlock(DateTime? waitStartedAt) {
    if (_settledWait == waitStartedAt) {
      return;
    }
    _settledWait = waitStartedAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(memoListProvider.notifier).settleUnlock(widget.memoId);
    });
  }

  Future<void> _open(Memo memo) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(memoListProvider.notifier).startWaiting(
          memo.id,
          notification: unlockNotificationContent(l10n, memo),
        );
  }

  Future<void> _extendWait() async {
    final l10n = AppLocalizations.of(context);
    final extended =
        await ref.read(memoListProvider.notifier).extendWait(widget.memoId);
    if (!mounted || extended == null) {
      return;
    }
    setState(() => _suggestionDismissed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.extendedWaitDone(formatWaitLength(l10n, extended)),
        ),
      ),
    );
  }

  Future<void> _stopWaiting() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(l10n.stopWaitingConfirmMessage);
    if (!confirmed) {
      return;
    }
    await ref.read(memoListProvider.notifier).cancelWaiting(widget.memoId);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(l10n.deleteConfirmMessage);
    if (!confirmed) {
      return;
    }
    await ref.read(memoListProvider.notifier).delete(widget.memoId);
    if (mounted) {
      context.go(AppRoutes.memoList);
    }
  }

  Future<bool> _confirm(String message) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionOk),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

/// まだ開こうとしていない状態。ここから待機が始まる。
class _LockedView extends StatelessWidget {
  const _LockedView({required this.memo, required this.onOpen});

  final Memo memo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wait = memo.unlockRule.expectedWait;

    return _CenteredColumn(
      children: [
        Icon(
          Icons.lock_outline,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(l10n.lockedBodyHidden, textAlign: TextAlign.center),
        if (wait != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.lockedWaitNotice(formatWaitLength(l10n, wait)),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.hourglass_top),
          label: Text(l10n.actionOpen),
        ),
      ],
    );
  }
}

/// 待機中。残り時間だけを見せ、本文には触れない。
class _WaitingView extends StatelessWidget {
  const _WaitingView({
    required this.remaining,
    required this.unlockAt,
    required this.now,
    required this.onStopWaiting,
  });

  final Duration? remaining;
  final DateTime? unlockAt;
  final DateTime now;
  final VoidCallback onStopWaiting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return _CenteredColumn(
      children: [
        Icon(
          Icons.hourglass_bottom,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(l10n.stateWaiting, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(
          remaining == null
              ? l10n.lockedBodyHidden
              : l10n.waitingRemaining(formatRemaining(l10n, remaining!)),
          style: theme.textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        if (unlockAt != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.waitingUnlockAt(formatUnlockTime(locale, unlockAt!, now)),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 24),
        Text(
          l10n.waitingKeepClosedNotice,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: onStopWaiting,
          child: Text(l10n.actionStopWaiting),
        ),
      ],
    );
  }
}

/// 解錠中。読めるのは再ロックまでの間だけ。
class _UnlockedView extends StatelessWidget {
  const _UnlockedView({
    required this.memo,
    required this.remaining,
    required this.showSuggestion,
    required this.onExtendWait,
    required this.onReview,
    required this.onDelete,
    required this.onDismissSuggestion,
  });

  final Memo memo;
  final Duration remaining;
  final bool showSuggestion;
  final VoidCallback onExtendWait;
  final VoidCallback onReview;
  final VoidCallback onDelete;
  final VoidCallback onDismissSuggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.lock_clock,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.unlockedRemaining(formatRemaining(l10n, remaining)),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSuggestion)
                  _Suggestions(
                    memo: memo,
                    onExtendWait: onExtendWait,
                    onReview: onReview,
                    onDelete: onDelete,
                    onDismiss: onDismissSuggestion,
                  ),
                SelectableText(memo.body, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 24),
                Text(
                  l10n.unlockedRelockNotice,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 開きすぎているメモへの提案。従うかどうかはユーザーが決める。
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.memo,
    required this.onExtendWait,
    required this.onReview,
    required this.onDelete,
    required this.onDismiss,
  });

  final Memo memo;
  final VoidCallback onExtendWait;
  final VoidCallback onReview;
  final VoidCallback onDelete;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wait = memo.unlockRule.expectedWait;
    final next = wait == null ? null : UnlockPolicy.nextWaitOption(wait);
    final suggestExtend = next != null &&
        memo.openCount >= UnlockPolicy.openCountForWaitSuggestion;
    final suggestReview =
        memo.openCount >= UnlockPolicy.openCountForReviewSuggestion;

    if (!suggestExtend && !suggestReview) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (suggestExtend)
            _SuggestionCard(
              title: l10n.suggestExtendTitle,
              message: l10n.suggestExtendMessage(
                formatWaitLength(l10n, next),
              ),
              actions: [
                TextButton(onPressed: onDismiss, child: Text(l10n.actionLater)),
                FilledButton(
                  onPressed: onExtendWait,
                  child: Text(l10n.actionExtendWait),
                ),
              ],
            ),
          if (suggestExtend && suggestReview) const SizedBox(height: 12),
          if (suggestReview)
            _SuggestionCard(
              title: l10n.suggestReviewTitle,
              message: l10n.suggestReviewMessage,
              actions: [
                TextButton(
                  onPressed: onDelete,
                  child: Text(l10n.actionDelete),
                ),
                TextButton(onPressed: onReview, child: Text(l10n.actionReview)),
              ],
            ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.title,
    required this.message,
    required this.actions,
  });

  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(message, style: theme.textTheme.bodyMedium),
            Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

/// 開封の記録。本文ではないのでロック中でも見せる。
class _OpenHistory extends StatelessWidget {
  const _OpenHistory({required this.memo, required this.now});

  /// 表示する履歴の件数。
  static const int _limit = 10;

  final Memo memo;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final history = memo.openedAt.reversed.take(_limit).toList();

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          ExpansionTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.openHistoryTitle),
            subtitle: Text(l10n.openCountLabel(memo.openCount)),
            children: [
              if (history.isEmpty)
                ListTile(
                  dense: true,
                  title: Text(
                    l10n.openHistoryEmpty,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                for (final at in history)
                  ListTile(
                    dense: true,
                    title: Text(
                      formatUnlockTime(locale, at, now),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CenteredColumn extends StatelessWidget {
  const _CenteredColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      );
}
