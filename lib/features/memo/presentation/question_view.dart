import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// 問いに1問ずつ答えてもらう画面。
///
/// 登録した順に出す。前の問いを受けて次の問いを置けるようにするため。
/// すべてに「はい」で答えたときだけ [onAccepted] を呼ぶ。
class QuestionView extends StatefulWidget {
  const QuestionView({
    super.key,
    required this.questions,
    required this.onAccepted,
    required this.onDeclined,
  });

  final List<String> questions;

  /// すべてに「はい」で答えたとき。
  final VoidCallback onAccepted;

  /// ひとつでも「いいえ」と答えたとき。
  final VoidCallback onDeclined;

  @override
  State<QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<QuestionView> {
  int _index = 0;

  List<String> get _questions => widget.questions;

  void _answerYes() {
    if (_index + 1 >= _questions.length) {
      widget.onAccepted();
      return;
    }
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.questionProgress(_index + 1, _questions.length),
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 24),
            Text(
              _questions[_index],
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: widget.onDeclined,
                  child: Text(l10n.actionNo),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _answerYes,
                  child: Text(l10n.actionYes),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
