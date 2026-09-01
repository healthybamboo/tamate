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

/// メモ一覧画面。
///
/// ロック中のメモは本文のプレビューを出さない。一覧から中身が読めてしまっては
/// 「開けないメモ」にならないため。
class MemoListPage extends ConsumerWidget {
  const MemoListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final memos = ref.watch(memoListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.memoListTitle)),
      body: memos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.errorGeneric)),
        data: (memos) => memos.isEmpty
            ? Center(
                child: Text(
                  l10n.memoListEmpty,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            : ListView.separated(
                itemCount: memos.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) => _MemoTile(memo: memos[index]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.memoNew),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _MemoTile extends ConsumerWidget {
  const _MemoTile({required this.memo});

  final Memo memo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // ロック中は時間で表示が変わらないので、秒ごとの更新もいらない。
    final clockNow = ref.read(clockProvider).now();
    final now =
        memo.lockStateAt(clockNow) is MemoLocked ? clockNow : watchNow(ref);
    final lockState = memo.lockStateAt(now);

    return ListTile(
      leading: Icon(_iconFor(lockState)),
      title: Text(
        memoDisplayTitle(l10n, memo),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusFor(l10n, lockState),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (lockState.canRead && memo.body.trim().isNotEmpty)
            Text(memo.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      isThreeLine: lockState.canRead && memo.body.trim().isNotEmpty,
      onTap: () => context.push(AppRoutes.memoDetail(memo.id)),
    );
  }

  IconData _iconFor(MemoLockState state) => switch (state) {
        MemoLocked() => Icons.lock_outline,
        MemoWaiting(:final running) =>
          running ? Icons.hourglass_bottom : Icons.pause_circle_outline,
        MemoUnlocked() => Icons.lock_open_outlined,
      };

  String _statusFor(AppLocalizations l10n, MemoLockState state) =>
      switch (state) {
        MemoLocked() => l10n.stateLocked,
        MemoWaiting(:final remaining, :final running) => switch (remaining) {
            null => running ? l10n.stateWaiting : l10n.waitingPaused,
            final left when running =>
              l10n.waitingRemaining(formatRemaining(l10n, left)),
            final left =>
              l10n.waitingRemainingPaused(formatRemaining(l10n, left)),
          },
        MemoUnlocked(:final remaining) =>
          l10n.unlockedRemaining(formatRemaining(l10n, remaining)),
      };
}
