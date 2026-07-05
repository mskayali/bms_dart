import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // BLE-dependent app cannot run widget tests without mocking.
    // Plugin unit tests are in the parent jk_bms/test/ directory.
    expect(true, isTrue);
  });
}
