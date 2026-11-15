import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/customer_filter.dart';
import '../controllers/tally_controller.dart';
import '../models.dart';
import '../utils.dart';

/// Text shown for a customer in pickers: "Ravi Stores · #1001 — Erode, Tamil Nadu".
/// Typing any part of it (name, code, area, district, state) finds the customer.
String pickerLabel(Customer cu) =>
    cu.place.isEmpty ? cu.label : '${cu.label} — ${cu.place}';

/// Customer picker. Shows the chosen customer; clicking it opens a search
/// window where you type part of the name, code, area, district or state and
/// click (or press Enter on) a result.
///
/// The box always shows the customer that is really selected: nothing is
/// selected until a result is chosen, so the text can never disagree with
/// the selection.
///
/// [allowAll] adds an "All customers" choice (value null) for filters.
/// [include] limits the list (e.g. to the state chosen in a filter).
/// [width] null = fill the available width.
class CustomerPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowAll;
  final String label;
  final String? errorText;
  final double? width;
  final bool compact; // small box with an outline, to match filter dropdowns
  final bool Function(Customer)? include;

  const CustomerPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowAll = false,
    this.label = 'Customer',
    this.errorText,
    this.width,
    this.compact = false,
    this.include,
  });

  Future<void> _open() async {
    final picked = await Get.dialog<String>(
        _CustomerSearchDialog(allowAll: allowAll, current: value, include: include));
    if (picked == null) return; // closed without choosing
    onChanged(picked == _allCustomers ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final cu = value == null ? null : c.customerById(value!);
    final text = value == null
        ? (allowAll ? 'All customers' : '')
        : (cu == null ? 'Deleted customer' : pickerLabel(cu));

    final field = InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: text.isEmpty,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Click to search customers',
          errorText: errorText,
          isDense: compact,
          border: compact ? const OutlineInputBorder() : const UnderlineInputBorder(),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Tooltip(
          message: text,
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Returned by the search window for "All customers" (null means cancelled).
const _allCustomers = '__all__';

/// Search window: type to narrow the list, click a customer or press Enter
/// for the first result.
class _CustomerSearchDialog extends StatefulWidget {
  final bool allowAll;
  final String? current;
  final bool Function(Customer)? include;
  const _CustomerSearchDialog({required this.allowAll, this.current, this.include});

  @override
  State<_CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<_CustomerSearchDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Every typed word must appear in the name, code, place or phone,
  /// e.g. "ravi erode" finds Ravi Stores in Erode.
  List<Customer> _results() {
    final c = Get.find<TallyController>();
    final words = _search.text.toLowerCase().replaceAll('#', ' ').split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    return c.customers.where((cu) {
      if (widget.include != null && !widget.include!(cu)) return false;
      final text = '${pickerLabel(cu)} ${cu.phone}'.toLowerCase();
      return words.every(text.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final results = _results();
    final showAll = widget.allowAll && _search.text.trim().isEmpty;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Choose customer'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(children: [
          TextField(
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Type name, code, area, district or state',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            // Search again with the text as it is now (the list on screen may
            // not have caught up with very fast typing)
            onSubmitted: (_) {
              final now = _results();
              if (now.isNotEmpty) Get.back(result: now.first.id);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${results.length} ${results.length == 1 ? 'customer' : 'customers'}'
              '${results.isNotEmpty && _search.text.trim().isNotEmpty ? ' · Enter picks the first' : ''}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(children: [
              if (showAll)
                ListTile(
                  leading: const Icon(Icons.groups),
                  title: const Text('All customers'),
                  selected: widget.current == null,
                  onTap: () => Get.back(result: _allCustomers),
                ),
              for (final cu in results)
                ListTile(
                  leading: CircleAvatar(radius: 6, backgroundColor: c.statusOf(cu.id).color),
                  title: Text(cu.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [cu.place, cu.phone].where((x) => x.isNotEmpty).join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: cu.id == widget.current,
                  onTap: () => Get.back(result: cu.id),
                ),
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(c.customers.isEmpty
                        ? 'No customers yet.'
                        : 'No customer matches "${_search.text.trim()}".'),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: Get.back, child: const Text('Cancel'))],
    );
  }
}

/// Customer / State / District filter row, used on several screens.
class CustomerFilterBar extends StatelessWidget {
  final CustomerFilter filter;
  final bool showCustomer;
  final bool showClear; // false when the screen has its own "Reset" button
  const CustomerFilterBar(this.filter,
      {super.key, this.showCustomer = true, this.showClear = true});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();

    return Obx(() {
      c.customers.length; // rebuild when customers change
      final state = filter.state.value;
      final district = filter.district.value;

      // Choices: states / districts that customers are in. The current choice
      // is always kept in the list, even if no customer has it any more.
      final states = c.statesInUse();
      if (state != null && !states.contains(state)) states.add(state);
      final districts = c.districtsIn(state);
      final districtValue = district == null
          ? null
          : districts.firstWhere((d) => d.toLowerCase() == district.toLowerCase(),
              orElse: () {
              districts.add(district);
              return district;
            });

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showCustomer)
            CustomerPicker(
              value: filter.customerId.value,
              allowAll: true,
              compact: true,
              width: 330,
              include: filter.inPlace, // only customers in the chosen state/district
              onChanged: (v) => filter.customerId.value = v,
            ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('state-filter-$state'),
              initialValue: state,
              isExpanded: true,
              menuMaxHeight: 420,
              decoration: const InputDecoration(
                labelText: 'State',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All states')),
                for (final s in states)
                  DropdownMenuItem<String?>(
                    value: s,
                    child: Text(s.isEmpty ? 'Not set' : s, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) =>
                  filter.setState(v, c.districtsIn, customerById: c.customerById),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('district-filter-$state-$districtValue'),
              initialValue: districtValue,
              isExpanded: true,
              menuMaxHeight: 420,
              decoration: const InputDecoration(
                labelText: 'District',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All districts')),
                for (final d in districts)
                  DropdownMenuItem<String?>(
                    value: d,
                    child: Text(d.isEmpty ? 'Not set' : d, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => filter.setDistrict(v, customerById: c.customerById),
            ),
          ),
          if (showClear && filter.isActive)
            TextButton.icon(
              onPressed: filter.reset,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Clear'),
            ),
        ],
      );
    });
  }
}
