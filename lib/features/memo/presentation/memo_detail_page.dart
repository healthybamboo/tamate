import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock/clock.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/memo_list_notifier.dart';
import '../domain/memo.dart';
import '../domain/memo_lock_state.dart';
import 'duration_format.dart';
import 'memo_display.dart';

/// メモを開く画面。
///
/// ロック中・待機中・解錠中のどれを見せるかは [Memo.lockStateAt] の結果で決まる。
/// 待機が終わるまで本文はウィジェットツリーにも載せない。
class MemoDetailPage extends ConsumerStatefulWidget {
  const MemoDetailPage({super.key, required this.memoId});

  final String memoId;

  @override
  ConsumerState<MemoDetailPage> createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends ConsumerState<MemoDetailPage> {
  /// 解錠時刻を記録済みの待機。待ち直したらまた記録する。
  DateTime? _settledWait;

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
        child: switch (lockState) {
          MemoLocked() => _LockedView(memo: memo, onOpen: () => _open(memo)),
          MemoWaiting(:final remaining, :final unlockAt) => _WaitingView(
              remaining: remaining,
              unlockAt: unlockAt,
              now: now,
              onStopWaiting: _stopWaiting,
            ),
          MemoUnlocked(:final remaining) => _UnlockedView(
              memo: memo,
              remaining: remaining,
            ),
        },
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
  const _UnlockedView({required this.memo, required this.remaining});

  final Memo memo;
  final Duration remaining;

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
                SelectableText(
                  memo.body,
                  style: theme.textTheme.bodyLarge,
                ),
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
