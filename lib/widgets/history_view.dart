import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/tally_controller.dart';
import '../models.dart';

String _when(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);

/// One edit / delete record: what changed (old → new) and the reason.
class HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final bool showCustomer;
  const HistoryCard(this.item, {super.key, this.showCustomer = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deleted = item.action == 'deleted';
    final color = deleted ? Colors.red.shade700 : Colors.blue.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon, what, customer, time
            Row(children: [
              Icon(deleted ? Icons.delete_outline : Icons.edit, size: 18, color: color),
              const SizedBox(width: 8),
              Text(deleted ? 'Deleted' : 'Edited',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  showCustomer ? '${item.what}  ·  ${item.customerLabel}' : item.what,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              const Spacer(),
              Text(_when(item.at), style: TextStyle(fontSize: 12, color: scheme.outline)),
            ]),
            const SizedBox(height: 10),

            // Changes
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                for (final c in item.changes)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16, bottom: 4),
                      child: Text(c.field, style: TextStyle(color: scheme.outline)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: deleted
                          ? Text(c.from,
                              style: const TextStyle(
                                  decoration: TextDecoration.lineThrough))
                          : Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: c.from,
                                  style: const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: Colors.grey)),
                              const TextSpan(text: '   →   '),
                              TextSpan(
                                  text: c.to,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ])),
                    ),
                  ]),
              ],
            ),
            const SizedBox(height: 8),

            // Reason
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text.rich(TextSpan(children: [
                const TextSpan(
                    text: 'Reason: ', style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: item.reason.isEmpty ? '(none given)' : item.reason),
              ])),
            ),
          ],
        ),
      ),
    );
  }
}

/// List of history cards, or a message when empty.
class HistoryList extends StatelessWidget {
  final List<HistoryItem> items;
  final bool showCustomer;
  final String emptyText;
  const HistoryList(this.items,
      {super.key, this.showCustomer = true, this.emptyText = 'No changes yet.'});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(emptyText)),
      );
    }
    return Column(children: [
      for (final h in items) HistoryCard(h, showCustomer: showCustomer),
    ]);
  }
}

/// Popup with the change history of one entry.
Future<void> showEntryHistory(String entryId) {
  final items = Get.find<TallyController>().historyOfEntry(entryId);
  return Get.dialog(AlertDialog(
    title: const Text('Change history'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(child: HistoryList(items, showCustomer: false)),
    ),
    actions: [TextButton(onPressed: Get.back, child: const Text('Close'))],
  ));
}

/// Small icon button shown on entries that were edited.
class EditedButton extends StatelessWidget {
  final String entryId;
  const EditedButton(this.entryId, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.find<TallyController>().wasEdited(entryId)) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Edited – see change history',
      icon: Icon(Icons.history, size: 18, color: Colors.blue.shade700),
      onPressed: () => showEntryHistory(entryId),
    );
  }
}

/// Asks for a reason before deleting. Returns the reason, or null if cancelled.
Future<String?> askDeleteReason(String message) =>
    Get.dialog<String>(_DeleteReasonDialog(message));

class _DeleteReasonDialog extends StatefulWidget {
  final String message;
  const _DeleteReasonDialog(this.message);

  @override
  State<_DeleteReasonDialog> createState() => _DeleteReasonDialogState();
}

class _DeleteReasonDialogState extends State<_DeleteReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  void _delete() {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Write why this is being deleted');
      return;
    }
    Get.back(result: _reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Are you sure?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reason for deleting *',
                hintText: 'e.g. Entered twice by mistake',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('The deleted details and this reason are kept in the change history.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _delete,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// "Reason for change" box shown in edit forms.
class ReasonField extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  const ReasonField({super.key, required this.controller, this.errorText});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'Reason for change *',
        hintText: 'e.g. Customer returned 5 kg / wrong price entered',
        helperText: 'Saved in the change history with the old and new values',
        errorText: errorText,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.amber.withValues(alpha: 0.08),
      ),
    );
  }
}
