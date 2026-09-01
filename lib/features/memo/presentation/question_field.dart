import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// 問いかけの編集欄。
///
/// 問いは複数登録でき、上から順に並ぶ（出すときは並べ替える）。よく使う問いは
/// 候補として出して、書き出す手間を減らす。
class QuestionField extends StatefulWidget {
  const QuestionField({
    super.key,
    required this.questions,
    required this.onChanged,
  });

  final List<String> questions;
  final ValueChanged<List<String>> onChanged;

  @override
  State<QuestionField> createState() => _QuestionFieldState();
}

class _QuestionFieldState extends State<QuestionField> {
  late final List<TextEditingController> _controllers = [
    for (final question in widget.questions)
      TextEditingController(text: question),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _publish() => widget.onChanged([for (final c in _controllers) c.text]);

  void _add([String text = '']) {
    setState(() => _controllers.add(TextEditingController(text: text)));
    _publish();
  }

  void _removeAt(int index) {
    setState(() => _controllers.removeAt(index).dispose());
    _publish();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final suggestions = [
      l10n.questionSuggestion1,
      l10n.questionSuggestion2,
      l10n.questionSuggestion3,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.questionsLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(l10n.questionsHelper, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (var index = 0; index < _controllers.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[index],
                    decoration: InputDecoration(hintText: l10n.questionHint),
                    onChanged: (_) => _publish(),
                    maxLines: null,
                  ),
                ),
                IconButton(
                  onPressed: () => _removeAt(index),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: l10n.actionDelete,
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(l10n.questionAdd),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final suggestion in suggestions)
              ActionChip(
                label: Text(suggestion),
                onPressed: () => _add(suggestion),
              ),
          ],
        ),
      ],
    );
  }
}
