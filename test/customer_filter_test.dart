import 'package:flutter_test/flutter_test.dart';
import 'package:ghee_tally/controllers/customer_filter.dart';
import 'package:ghee_tally/data/indian_states.dart';
import 'package:ghee_tally/models.dart';

void main() {
  final ravi = Customer(id: '1', code: '1001', name: 'Ravi', district: 'Erode', state: 'Tamil Nadu');
  final ravi2 = Customer(id: '2', code: '1002', name: 'Ravi', district: 'erode ', state: 'Tamil Nadu');
  final kochi = Customer(id: '3', code: '1003', name: 'Kochi Mart', district: 'Ernakulam', state: 'Kerala');
  final old = Customer(id: '4', code: '1004', name: 'Old shop'); // no state, no district
  final all = [ravi, ravi2, kochi, old];

  test('no filter keeps everyone', () {
    final f = CustomerFilter();
    expect(f.isActive, isFalse);
    expect(f.matchingIds(all), isNull);
  });

  test('state filter', () {
    final f = CustomerFilter()..state.value = 'Tamil Nadu';
    expect(f.matchingIds(all), {'1', '2'});
  });

  test('district filter ignores capitals and spaces', () {
    final f = CustomerFilter()..district.value = 'Erode';
    expect(f.matchingIds(all), {'1', '2'});
  });

  test('"Not set" finds customers without a state', () {
    final f = CustomerFilter()..state.value = '';
    expect(f.matchingIds(all), {'4'});
  });

  test('one customer', () {
    final f = CustomerFilter()..customerId.value = '3';
    expect(f.matchingIds(all), {'3'});
  });

  test('changing state clears a district from another state', () {
    final f = CustomerFilter()
      ..state.value = 'Tamil Nadu'
      ..district.value = 'Erode';
    List<String> districtsIn(String? st) => switch (st) {
          'Kerala' => ['Ernakulam'],
          'Tamil Nadu' => ['Erode'],
          _ => ['Erode', 'Ernakulam', ''],
        };
    f.setState('Kerala', districtsIn);
    expect(f.district.value, isNull);
    f
      ..setState('Tamil Nadu', districtsIn)
      ..district.value = 'erode';
    f.setState(null, districtsIn); // "All states" keeps Erode
    expect(f.district.value, 'erode');
  });

  test('describe and reset', () {
    final f = CustomerFilter()
      ..state.value = 'Tamil Nadu'
      ..district.value = '';
    expect(f.describe((id) => id), 'Tamil Nadu · No district');
    f.reset();
    expect(f.isActive, isFalse);
  });

  test('all 28 states and 8 union territories, no duplicates', () {
    expect(indianStates.length, 36);
    expect(indianStates.toSet().length, 36);
    expect(indianStates, containsAll(['Tamil Nadu', 'Kerala', 'Delhi', 'Ladakh', 'Puducherry']));
  });

  test('picking a state or district drops a chosen customer who is not there', () {
    Customer? byId(String id) => all.firstWhere((c) => c.id == id);
    List<String> districtsIn(String? st) => ['Erode', 'Ernakulam', ''];

    final f = CustomerFilter()..customerId.value = '3'; // Kochi Mart, Kerala
    f.setState('Kerala', districtsIn, customerById: byId);
    expect(f.customerId.value, '3'); // still in Kerala: kept
    f.setState('Tamil Nadu', districtsIn, customerById: byId);
    expect(f.customerId.value, isNull); // not in Tamil Nadu: cleared
    expect(f.matchingIds(all), {'1', '2'});

    f.customerId.value = '1'; // Ravi, Erode
    f.setDistrict('Salem', customerById: byId);
    expect(f.customerId.value, isNull);
  });

  test('inPlace ignores the chosen customer', () {
    final f = CustomerFilter()
      ..customerId.value = '3'
      ..state.value = 'Tamil Nadu';
    expect(f.inPlace(ravi), isTrue); // used to list customers in the picker
    expect(f.matches(ravi), isFalse); // but Ravi is not the chosen customer
  });
}
