import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../widgets/history_view.dart';

/// Every edit and deletion in the app, newest first, with the reasons.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _search = '';
  String? _action; // null = all, 'edited', 'deleted'

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change history', style: t.headlineMedium),
          const SizedBox(height: 4),
          const Text('Every edit and deletion, with the old and new values and the reason.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search customer, code or reason',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              for (final (value, label) in [
                (null, 'All'),
                ('edited', 'Edits'),
                ('deleted', 'Deletions'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _action == value,
                  onSelected: (_) => setState(() => _action = value),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() {
              final items = c.history.reversed.where((h) {
                final matchAction = _action == null || h.action == _action;
                final q = _search.replaceAll('#', '');
                final matchText = q.isEmpty ||
                    h.customerLabel.toLowerCase().contains(q) ||
                    h.reason.toLowerCase().contains(q) ||
                    h.what.toLowerCase().contains(q);
                return matchAction && matchText;
              }).toList();
              return ListView(children: [
                HistoryList(items,
                    emptyText: c.history.isEmpty
                        ? 'No edits or deletions yet. When an entry or customer is '
                            'changed, it will be listed here with the reason.'
                        : 'Nothing matches this search.'),
              ]);
            }),
          ),
        ],
      ),
    );
  }
}
