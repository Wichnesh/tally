import 'package:get/get.dart';

import '../models.dart';

/// Filter by customer, state and district. Each screen keeps its own copy.
///
/// A value of null means "All". An empty string '' means "Not set"
/// (customers who have no state / district filled in).
class CustomerFilter {
  final customerId = RxnString();
  final state = RxnString();
  final district = RxnString();

  /// Reads all three values (no short-cut), so a screen that calls this
  /// inside Obx redraws when ANY of them changes.
  bool get isActive {
    final id = customerId.value, st = state.value, d = district.value;
    return id != null || st != null || d != null;
  }

  void reset() {
    customerId.value = null;
    state.value = null;
    district.value = null;
  }

  /// Picking a state clears a district that belongs to another state,
  /// and a chosen customer who is not in the new state.
  void setState(String? value, List<String> Function(String?) districtsIn,
      {Customer? Function(String id)? customerById}) {
    state.value = value;
    final d = district.value;
    if (d != null &&
        !districtsIn(value).any((x) => x.toLowerCase() == d.toLowerCase())) {
      district.value = null;
    }
    _dropCustomerOutsidePlace(customerById);
  }

  /// Picking a district clears a chosen customer who is not in it.
  void setDistrict(String? value, {Customer? Function(String id)? customerById}) {
    district.value = value;
    _dropCustomerOutsidePlace(customerById);
  }

  void _dropCustomerOutsidePlace(Customer? Function(String id)? customerById) {
    final id = customerId.value;
    if (id == null || customerById == null) return;
    final cu = customerById(id);
    if (cu == null || !inPlace(cu)) customerId.value = null;
  }

  /// True if [c] is in the chosen state and district (the chosen customer is
  /// not checked). District matching ignores capitals and extra spaces, so
  /// "erode" and "Erode " count as the same district.
  bool inPlace(Customer c) {
    final st = state.value, d = district.value; // read both, for Obx
    if (st != null && c.state != st) return false;
    if (d != null && c.district.trim().toLowerCase() != d.trim().toLowerCase()) {
      return false;
    }
    return true;
  }

  /// True if [c] passes the whole filter (customer, state and district).
  bool matches(Customer c) {
    final id = customerId.value;
    final place = inPlace(c);
    return (id == null || c.id == id) && place;
  }

  /// Ids of the customers that pass, or null when nothing is filtered
  /// (null = keep every entry, including entries of deleted customers).
  Set<String>? matchingIds(Iterable<Customer> customers) =>
      isActive ? {for (final c in customers.where(matches)) c.id} : null;

  /// Short text for what is selected, e.g. "Tamil Nadu · Erode".
  String describe(String Function(String id) customerName) => [
        if (customerId.value != null) customerName(customerId.value!),
        if (state.value != null) state.value!.isEmpty ? 'No state' : state.value!,
        if (district.value != null)
          district.value!.isEmpty ? 'No district' : district.value!,
      ].join(' · ');
}
