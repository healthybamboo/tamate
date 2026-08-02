import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/memo_list_notifier.dart';

/// メモの新規作成 / 編集画面。
///
/// [memoId] が null なら新規作成。
class MemoEditPage extends ConsumerStatefulWidget {
  const MemoEditPage({super.key, this.memoId});

  final String? memoId;

  @override
  ConsumerState<MemoEditPage> createState() => _MemoEditPageState();
}

class _MemoEditPageState extends ConsumerState<MemoEditPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  bool get _isNew => widget.memoId == null;

  @override
  void initState() {
    super.initState();
    final memo = _isNew ? null : ref.read(memoProvider(widget.memoId!));
    _titleController = TextEditingController(text: memo?.title ?? '');
    _bodyController = TextEditingController(text: memo?.body ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(memoListProvider.notifier);
    final title = _titleController.text;
    final body = _bodyController.text;

    if (_isNew) {
      await notifier.add(title: title, body: body);
    } else {
      await notifier.edit(id: widget.memoId!, title: title, body: body);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.deleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await ref.read(memoListProvider.notifier).delete(widget.memoId!);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.memoNewTitle : l10n.memoEditTitle),
        actions: [
          if (!_isNew)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.actionDelete,
            ),
          TextButton(onPressed: _save, child: Text(l10n.actionSave)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: l10n.memoTitleLabel),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: InputDecoration(
                  labelText: l10n.memoBodyLabel,
                  alignLabelWithHint: true,
                ),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
