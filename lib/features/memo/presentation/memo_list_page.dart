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
/// 「開けないメモ」にならないため。状態は色の付いたラベルで見分ける。
class MemoListPage extends ConsumerWidget {
  const MemoListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final memos = ref.watch(memoListProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.memoListTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (_summary(l10n, memos.valueOrNull, ref) case final summary?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  summary,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
      body: memos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.errorGeneric)),
        data: (memos) => memos.isEmpty
            ? const _EmptyView()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: memos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _MemoCard(memo: memos[index]),
              ),
      ),
      floatingActionButton: memos.valueOrNull?.isEmpty ?? false
          ? null
          : FloatingActionButton(
              onPressed: () => context.push(AppRoutes.memoNew),
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// 見出しの下に出す一行。何件あって、いま何件読めるのかを見せる。
///
/// メモが無いときは空状態の案内があるので出さない。
String? _summary(AppLocalizations l10n, List<Memo>? memos, WidgetRef ref) {
  if (memos == null || memos.isEmpty) {
    return null;
  }

  final now = ref.read(clockProvider).now();
  var readable = 0;
  var waiting = 0;
  for (final memo in memos) {
    switch (memo.lockStateAt(now)) {
      case MemoUnlocked():
        readable++;
      case MemoWaiting() || MemoAwaitingAnswers():
        waiting++;
      case MemoLocked():
        break;
    }
  }

  return [
    l10n.memoListSummaryTotal(memos.length),
    if (readable > 0) l10n.memoListSummaryReadable(readable),
    if (waiting > 0) l10n.memoListSummaryWaiting(waiting),
  ].join(l10n.summarySeparator);
}

/// メモがまだ1件も無いとき。作るところまで案内する。
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(l10n.memoListEmpty, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.memoListEmptyDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.memoNew),
              icon: const Icon(Icons.add),
              label: Text(l10n.actionCreateMemo),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoCard extends ConsumerWidget {
  const _MemoCard({required this.memo});

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
    final preview = memo.body.trim();

    return Card(
      child: InkWell(
        onTap: () => context.push(AppRoutes.memoDetail(memo.id)),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      memoDisplayTitle(l10n, memo),
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _StateBadge(state: lockState),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _detail(l10n, lockState),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (lockState.canRead && preview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (memo.openCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.openCountLabel(memo.openCount),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 状態の下に出す一行。ロック中は、開いたら何が待っているかを見せる。
  String _detail(AppLocalizations l10n, MemoLockState state) => switch (state) {
        MemoLocked() => _lockedDetail(l10n),
        MemoWaiting(:final remaining) => remaining == null
            ? l10n.stateWaiting
            : l10n.waitingRemaining(formatRemaining(l10n, remaining)),
        MemoAwaitingAnswers() => l10n.stateAwaitingAnswers,
        MemoUnlocked(:final remaining) =>
          l10n.unlockedRemaining(formatRemaining(l10n, remaining)),
      };

  String _lockedDetail(AppLocalizations l10n) {
    final wait = memo.unlockRule.expectedWait;
    final asksQuestions = memo.unlockRule.questions.isNotEmpty;

    if (wait == null) {
      return asksQuestions ? l10n.lockedQuestionSummary : l10n.lockedBodyHidden;
    }
    final duration = formatWaitLength(l10n, wait);
    return asksQuestions
        ? l10n.lockedWaitAndQuestionSummary(duration)
        : l10n.lockedWaitSummary(duration);
  }
}

/// 状態を示す小さなラベル。
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final MemoLockState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (label, background, foreground) = switch (state) {
      MemoLocked() => (
          l10n.stateLocked,
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      MemoWaiting() => (
          l10n.stateWaiting,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      MemoAwaitingAnswers() => (
          l10n.stateAwaitingAnswers,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      MemoUnlocked() => (l10n.stateUnlocked, scheme.primary, scheme.onPrimary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(state), size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }

  IconData _icon(MemoLockState state) => switch (state) {
        MemoLocked() => Icons.lock_outline,
        MemoWaiting() => Icons.hourglass_bottom,
        MemoAwaitingAnswers() => Icons.help_outline,
        MemoUnlocked() => Icons.lock_open_outlined,
      };
}
