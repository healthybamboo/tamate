import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/memo_list_notifier.dart';
import '../domain/memo.dart';

/// メモ一覧画面。
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

class _MemoTile extends StatelessWidget {
  const _MemoTile({required this.memo});

  final Memo memo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = memo.title.trim().isEmpty ? l10n.memoUntitled : memo.title;

    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: memo.body.trim().isEmpty
          ? null
          : Text(memo.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => context.push(AppRoutes.memoEdit(memo.id)),
    );
  }
}
