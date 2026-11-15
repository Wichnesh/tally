import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../pages/customer_detail_page.dart';
import '../utils.dart';

/// Small box showing one number, e.g. "Total sales ₹1,00,000".
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const StatCard(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: color == null
            ? null
            : Border(left: BorderSide(color: color!, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(value,
              style: t.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// Coloured pill: "35% · Red alert"
class StatusChip extends StatelessWidget {
  final double? pct;
  const StatusChip(this.pct, {super.key});

  @override
  Widget build(BuildContext context) {
    final status = Get.find<TallyController>().statusFor(pct);
    final text =
        pct == null ? status.label : '${pct!.toStringAsFixed(0)}% · ${status.label}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: status.color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// One customer row with status colour. Tap opens the customer page.
class CustomerTile extends StatelessWidget {
  final String customerId;
  const CustomerTile(this.customerId, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final customer = c.customerById(customerId)!;
    final sold = c.soldOf(customerId);
    final paid = c.paidOf(customerId);
    final status = c.statusOf(customerId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: status.color,
          foregroundColor: Colors.white,
          child: Text(customer.name.isEmpty ? '?' : customer.name[0].toUpperCase()),
        ),
        title: Row(children: [
          Flexible(
            child: Text(customer.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          CodeChip(customer.code),
        ]),
        subtitle: Text([
          if (customer.place.isNotEmpty) customer.place,
          'Sold ${money(sold)}',
          'Paid ${money(paid)}',
        ].join('   ·   ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Balance', style: TextStyle(fontSize: 11)),
                Text(money(sold - paid),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(width: 16),
            SizedBox(width: 130, child: Align(
              alignment: Alignment.centerRight,
              child: StatusChip(c.percent(sold, paid)),
            )),
          ],
        ),
        onTap: () => Get.to(() => CustomerDetailPage(customerId: customerId)),
      ),
    );
  }
}

/// Small grey "#1001" tag.
class CodeChip extends StatelessWidget {
  final String code;
  const CodeChip(this.code, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('#$code',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
    );
  }
}
