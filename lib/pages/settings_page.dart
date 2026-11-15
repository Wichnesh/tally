import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../utils.dart';
import '../widgets/cash_dialog.dart';

/// Adjust the global Red / Yellow / Green levels.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final t = Theme.of(context).textTheme;

    return Obx(() {
      final red = c.redBelow.value;
      final green = c.greenFrom.value;

      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Settings', style: t.headlineMedium),
          const SizedBox(height: 8),
          const Text(
              'A customer\'s colour is based on how much of their total purchase they have paid.\n'
              'Example: bought ₹1,00,000 and paid ₹30,000 → 30% paid.'),
          const SizedBox(height: 24),

          // Preview bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 36,
              child: Row(children: [
                _zone(red, PayStatus.red, '0–${red.toInt()}%'),
                _zone(green - red, PayStatus.yellow, '${red.toInt()}–${green.toInt()}%'),
                _zone(100 - green, PayStatus.green, '${green.toInt()}–100%'),
              ]),
            ),
          ),
          const SizedBox(height: 32),

          Text('Red alert when paid is below ${red.toInt()}%', style: t.titleMedium),
          Slider(
            value: red,
            min: 0,
            max: 100,
            divisions: 20,
            label: '${red.toInt()}%',
            activeColor: PayStatus.red.color,
            onChanged: (v) => c.setLevels(v, v > green ? v : green),
          ),
          const SizedBox(height: 16),
          Text('Green when paid is ${green.toInt()}% or more', style: t.titleMedium),
          Slider(
            value: green,
            min: 0,
            max: 100,
            divisions: 20,
            label: '${green.toInt()}%',
            activeColor: PayStatus.green.color,
            onChanged: (v) => c.setLevels(v < red ? v : red, v),
          ),
          const SizedBox(height: 16),
          Text('Between ${red.toInt()}% and ${green.toInt()}% the customer is shown in yellow.',
              style: t.bodyMedium),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => c.setLevels(40, 75),
            child: const Text('Reset to 40% / 75%'),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 16),

          // ----- Price formula -----
          Text('Price formula', style: t.titleLarge),
          const SizedBox(height: 6),
          Text('Price per kg = Percent × Rate ÷ ${numText(c.priceDivisor.value)}'),
          const SizedBox(height: 4),
          Text('Used in the entry form. Changing the number below affects new prices '
              'only; saved entries keep their price.', style: t.bodySmall),
          const SizedBox(height: 12),
          _DivisorField(key: ValueKey(c.priceDivisor.value)),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 16),

          // ----- Cash book -----
          Text('Cash book accounts', style: t.titleLarge),
          const SizedBox(height: 6),
          const Text('Where the shop\'s money is kept. Each has its own opening and '
              'closing balance in the Cash book.'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in c.accounts)
              Chip(
                avatar: Icon(
                    a.toLowerCase().contains('cash')
                        ? Icons.payments_outlined
                        : Icons.account_balance_outlined,
                    size: 18),
                label: Text(a),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Add account'),
              onPressed: () async {
                final name =
                    await askName('New account', 'e.g. SBI current account, Petty cash');
                if (name != null) c.addAccount(name);
              },
            ),
          ]),
          const SizedBox(height: 24),
          Text('Customer payments go to', style: t.titleMedium),
          const SizedBox(height: 6),
          const Text('When a customer pays, the money is added to this account in the '
              'Cash book, depending on the payment mode.'),
          const SizedBox(height: 12),
          for (final mode in ['', ...c.paymentModes])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                  width: 200,
                  child: Text(mode.isEmpty ? 'No payment mode' : mode,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.arrow_forward, size: 18),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('mode-$mode-${c.accountForMode(mode)}-${c.accounts.length}'),
                    initialValue: c.accounts.contains(c.accountForMode(mode))
                        ? c.accountForMode(mode)
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: [
                      for (final a in c.accounts) DropdownMenuItem(value: a, child: Text(a)),
                    ],
                    onChanged: (v) {
                      if (v != null) c.setModeAccount(mode, v);
                    },
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 40),
          Text('Data is saved automatically on this computer.', style: t.bodySmall),
        ],
      );
    });
  }

  Widget _zone(double width, PayStatus s, String text) {
    if (width <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: (width * 10).round(),
      child: Container(
        color: s.color,
        alignment: Alignment.center,
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// The number the formula divides by (default 1326).
class _DivisorField extends StatefulWidget {
  const _DivisorField({super.key});

  @override
  State<_DivisorField> createState() => _DivisorFieldState();
}

class _DivisorFieldState extends State<_DivisorField> {
  final c = Get.find<TallyController>();
  late final _text = TextEditingController(text: numText(c.priceDivisor.value));
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseNum(_text.text);
    if (v <= 0) {
      setState(() => _error = 'Enter a number above 0');
      return;
    }
    c.setPriceDivisor(v);
    Get.snackbar('Saved', 'Price per kg = Percent × Rate ÷ ${numText(v)}',
        snackPosition: SnackPosition.BOTTOM, maxWidth: 480);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 200,
        child: TextField(
          controller: _text,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Divide by',
            errorText: _error,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      const SizedBox(width: 12),
      FilledButton(onPressed: _save, child: const Text('Save')),
      const SizedBox(width: 8),
      TextButton(
        onPressed: () {
          _text.text = numText(TallyController.defaultPriceDivisor);
          _save();
        },
        child: Text('Reset to ${numText(TallyController.defaultPriceDivisor)}'),
      ),
    ]);
  }
}
