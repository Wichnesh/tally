import 'package:flutter_test/flutter_test.dart';
import 'package:ghee_tally/utils.dart';

void main() {
  test('money uses Indian format', () {
    expect(money(100000), contains('1,00,000'));
  });

  test('price per kg formula: percent × rate ÷ 1326', () {
    expect(priceFromFormula(82.5, 8000, 1326), 497.74); // 497.7375 -> 497.74
    expect(priceFromFormula(80, 1326, 1326), 80);
    expect(priceFromFormula(82.5, 8000, 0), 0); // never divide by zero
    expect(perKg(497.74), '₹497.74');
    expect(perKg(520), '₹520');
    expect(formulaText(82.5, 8000), '82.5% × ₹8,000');
    expect(formulaText(null, null), '');
  });
}
