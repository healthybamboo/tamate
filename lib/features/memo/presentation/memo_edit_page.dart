import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock/clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/memo_list_notifier.dart';
import '../domain/generated_code.dart';
import '../domain/unlock_policy.dart';
import '../domain/unlock_rule.dart';
import 'duration_format.dart';

/// メモの新規作成 / 編集画面。
///
/// [memoId] が null なら新規作成。編集は解錠中のメモだけができる。
class MemoEditPage extends ConsumerStatefulWidget {
  const MemoEditPage({super.key, this.memoId});

  final String? memoId;

  @override
  ConsumerState<MemoEditPage> createState() => _MemoEditPageState();
}

class _MemoEditPageState extends ConsumerState<MemoEditPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  /// 新規作成時に選んでいる待機時間。作成後は変更できない。
  Duration _waitDuration = UnlockPolicy.defaultWait;

  /// 生成した4桁のコードを本文に入れたか。保存すると読めなくなる。
  bool _generatedCode = false;

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
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(memoListProvider.notifier);
    final title = _titleController.text;
    final body = _bodyController.text;

    if (_isNew) {
      await notifier.add(
        title: title,
        body: body,
        unlockRule: WaitDurationUnlockRule(_waitDuration),
      );
    } else {
      final saved = await notifier.edit(
        id: widget.memoId!,
        title: title,
        body: body,
      );
      if (!saved) {
        // 入力している間に閲覧可能時間が切れた場合。
        _leave(message: l10n.editRejectedRelocked);
        return;
      }
    }
    _leave();
  }

  /// 画面を閉じる。[message] があればスナックバーで知らせる。
  void _leave({String? message}) {
    if (!mounted) {
      return;
    }
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).pop();
  }

  /// 4桁のコードを作って本文に入れる。
  ///
  /// スクリーンタイムのパスコードのように「覚えていては意味がない」値を、
  /// 設定先に入力したあと自分では覚えずに預けるための入り口。
  void _generateCode() {
    setState(() {
      _generatedCode = true;
      _bodyController.text = GeneratedCode.create();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (!_isNew) {
      final memo = ref.watch(memoProvider(widget.memoId!));
      final canEdit =
          memo?.lockStateAt(ref.read(clockProvider).now()).canRead ?? false;
      if (!canEdit) {
        // 再ロックされた、あるいは削除された。編集させずに戻す。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _leave(message: l10n.editRejectedRelocked);
        });
        return const Scaffold(body: SizedBox.shrink());
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.memoNewTitle : l10n.memoEditTitle),
        actions: [
          TextButton(onPressed: _save, child: Text(l10n.actionSave)),
        ],
      ),
      body: SafeArea(
        child: Padding(
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
              if (_isNew) ...[
                _WaitDurationField(
                  value: _waitDuration,
                  onChanged: (value) => setState(() => _waitDuration = value),
                ),
                const SizedBox(height: 16),
              ],
              if (_isNew) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _generateCode,
                    icon: const Icon(Icons.pin_outlined),
                    label: Text(l10n.generateCodeAction),
                  ),
                ),
                if (_generatedCode)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.generateCodeNotice,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
              ],
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
      ),
    );
  }
}

/// 待機時間の選択。選択肢は [UnlockPolicy.waitOptions]。
class _WaitDurationField extends StatelessWidget {
  const _WaitDurationField({required this.value, required this.onChanged});

  final Duration value;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.memoWaitDurationLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<Duration>(
            segments: [
              for (final option in UnlockPolicy.waitOptions)
                ButtonSegment<Duration>(
                  value: option,
                  label: Text(formatWaitLength(l10n, option)),
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.memoWaitDurationHelper, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
