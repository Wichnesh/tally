import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/nav_controller.dart';
import '../controllers/tally_controller.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/customer_dialog.dart';
import '../widgets/customer_filter_bar.dart';

/// List of all customers with search and colour filter.
class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String _search = '';
  PayStatus? _filter; // null = show all

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Customers', style: t.headlineMedium),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => openCustomerDialog(),
              icon: const Icon(Icons.person_add),
              label: const Text('Add customer'),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search code, name, phone or place',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final s in [PayStatus.red, PayStatus.yellow, PayStatus.green])
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: s.color, radius: 6),
                  label: Text(s.label),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = s),
                ),
            ],
          ),
          const SizedBox(height: 12),
          CustomerFilterBar(Get.find<NavController>().customersFilter, showCustomer: false),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() {
              final place = Get.find<NavController>().customersFilter;
              final list = c.customers.where((cu) {
                final matchText = _search.isEmpty ||
                    cu.name.toLowerCase().contains(_search) ||
                    cu.code.toLowerCase().contains(_search.replaceAll('#', '')) ||
                    cu.phone.contains(_search) ||
                    cu.place.toLowerCase().contains(_search);
                final matchStatus = _filter == null || c.statusOf(cu.id) == _filter;
                return place.matches(cu) && matchText && matchStatus;
              }).toList();

              if (c.customers.isEmpty) {
                return const Center(
                    child: Text('No customers yet. Press "Add customer" to start.'));
              }
              if (list.isEmpty) {
                return const Center(child: Text('No customers match this filter.'));
              }
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Showing ${list.length} of ${c.customers.length} customers',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                for (final cu in list) CustomerTile(cu.id),
              ]);
            }),
          ),
        ],
      ),
    );
  }
}
