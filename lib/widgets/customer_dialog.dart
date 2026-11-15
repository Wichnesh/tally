import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../data/indian_states.dart';
import '../models.dart';
import '../utils.dart';
import 'history_view.dart';
import 'proof_tile.dart';

/// Add a new customer, or edit an existing one.
Future<void> openCustomerDialog([Customer? customer]) =>
    Get.dialog(CustomerDialog(customer: customer));

class CustomerDialog extends StatefulWidget {
  final Customer? customer;
  const CustomerDialog({super.key, this.customer});

  @override
  State<CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<CustomerDialog> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(
      text: widget.customer?.code ?? Get.find<TallyController>().nextCode());
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _location = TextEditingController(text: widget.customer?.location ?? '');
  late final _district = TextEditingController(text: widget.customer?.district ?? '');
  final _districtFocus = FocusNode();
  // '' = not set. A new customer starts with the state used last time.
  late String _state = widget.customer?.state ??
      (indianStates.contains(Get.find<TallyController>().lastState)
          ? Get.find<TallyController>().lastState
          : '');
  late final _proofs = [...?widget.customer?.proofs];

  // From the old (paper) book
  late final _oldBought = TextEditingController(
      text: _num(widget.customer?.openingBought ?? 0));
  late final _oldPaid =
      TextEditingController(text: _num(widget.customer?.openingPaid ?? 0));
  late DateTime _oldDate = widget.customer?.openingDate ?? dateOnly(DateTime.now());

  static String _num(double v) => v == 0 ? '' : numText(v);

  Future<void> _pickOldDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _oldDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _oldDate = dateOnly(d));
  }
  final _reason = TextEditingController(); // only when editing
  String? _reasonError;
  bool _saving = false;

  @override
  void dispose() {
    _districtFocus.dispose();
    super.dispose();
  }

  /// District suggestions: districts already typed for this state
  /// (or for any state when no state is chosen) that contain the typed text.
  Iterable<String> _districtOptions(TextEditingValue v) {
    final typed = v.text.trim();
    return Get.find<TallyController>()
        .districtsIn(_state.isEmpty ? null : _state)
        .where((d) => d.isNotEmpty && d.toLowerCase().contains(typed.toLowerCase()))
        // Hide only an exact match. "Erode" is still offered when "erode" was
        // typed, so the existing spelling can be picked.
        .where((d) => d != typed)
        .toList();
  }

  /// The State changed: work out the district suggestions again for the new
  /// state (the suggestion list only refreshes when the district text changes).
  void _changeState(String? v) {
    setState(() => _state = v ?? '');
    final typed = _district.value;
    _district.value = TextEditingValue.empty;
    _district.value = typed;
  }

  Future<void> _pickProofs() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose proof files',
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'heic', 'webp', 'pdf'],
    );
    setState(() {
      for (final f in files) {
        if (f.path != null && !_proofs.contains(f.path)) _proofs.add(f.path!);
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    final c = Get.find<TallyController>();

    // Editing: nothing changed -> just close. Changed -> reason is required.
    final old = widget.customer;
    if (old != null) {
      final changes = c.diff(
          c.customerFields(old),
          c.customerFields(Customer(
            id: old.id,
            code: _code.text.trim(),
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            location: _location.text.trim(),
            district: _district.text.trim(),
            state: _state,
            proofs: _proofs,
            openingBought: parseNum(_oldBought.text),
            openingPaid: parseNum(_oldPaid.text),
            openingDate: parseNum(_oldBought.text) == 0 && parseNum(_oldPaid.text) == 0
                ? null
                : _oldDate,
          )));
      if (changes.isEmpty) {
        Get.back();
        return;
      }
      if (_reason.text.trim().isEmpty) {
        setState(() => _reasonError = 'Write why you are changing these details');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await Get.find<TallyController>().saveCustomer(
        existing: widget.customer,
        code: _code.text.trim(),
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        location: _location.text.trim(),
        district: _district.text.trim(),
        state: _state,
        proofs: _proofs,
        openingBought: parseNum(_oldBought.text),
        openingPaid: parseNum(_oldPaid.text),
        openingDate: _oldDate,
        reason: _reason.text.trim(),
      );
      Get.back();
    } catch (e) {
      setState(() => _saving = false);
      Get.snackbar('Could not save', 'A proof file could not be copied: $e',
          snackPosition: SnackPosition.BOTTOM, maxWidth: 500);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'New customer' : 'Edit customer'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Customer code *',
                    prefixIcon: Icon(Icons.tag),
                    helperText: 'Unique for every customer. Filled in automatically; you can change it.',
                  ),
                  validator: (v) {
                    final code = (v ?? '').trim();
                    if (code.isEmpty) return 'Enter a code';
                    if (Get.find<TallyController>()
                        .isCodeTaken(code, exceptId: widget.customer?.id)) {
                      return 'Code $code is already used by another customer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Customer name *', prefixIcon: Icon(Icons.person)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone number', prefixIcon: Icon(Icons.phone)),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _state,
                        isExpanded: true,
                        menuMaxHeight: 420,
                        decoration: const InputDecoration(
                            labelText: 'State', prefixIcon: Icon(Icons.map_outlined)),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('— Not set —')),
                          // Keep an old value that is not in the list, so it is not lost
                          if (_state.isNotEmpty && !indianStates.contains(_state))
                            DropdownMenuItem(value: _state, child: Text(_state)),
                          for (final st in indianStates)
                            DropdownMenuItem(
                                value: st,
                                child: Text(st, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: _changeState,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Autocomplete<String>(
                        textEditingController: _district,
                        focusNode: _districtFocus,
                        optionsBuilder: _districtOptions,
                        fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                            TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'District',
                            hintText: 'Type the district',
                            prefixIcon: Icon(Icons.location_city),
                          ),
                          onFieldSubmitted: (_) => onSubmit(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(
                    labelText: 'Area / Town',
                    hintText: 'Street, village or town (optional)',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 20),

                // ----- From the old book (optional) -----
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text('From your old book (optional)',
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        TextButton.icon(
                          onPressed: _pickOldDate,
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text('As on ${shortDate(_oldDate)}'),
                        ),
                      ]),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _oldBought,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Total purchases before (₹)'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _oldPaid,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Total paid before (₹)'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Balance due from old book: '
                        '${money(parseNum(_oldBought.text) - parseNum(_oldPaid.text))}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Only know the balance? Enter it in "Total purchases before" '
                        'and leave "Total paid before" empty.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ----- Proofs (optional) -----
                Row(children: [
                  Text('Proofs (optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickProofs,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload'),
                  ),
                ]),
                Text('ID card, GST certificate, shop photo… Photos or PDF.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (_proofs.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final path in _proofs)
                      ProofTile(path,
                          onRemove: () => setState(() => _proofs.remove(path))),
                  ]),
                if (widget.customer != null) ...[
                  const SizedBox(height: 20),
                  ReasonField(controller: _reason, errorText: _reasonError),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
