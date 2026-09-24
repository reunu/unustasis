import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/extended_response.dart' as core;
import 'package:unustasis/service/ble_commands.dart' as legacy;

void main() {
  test('legacy command exports preserve protocol exception identity', () async {
    const error = legacy.ExtendedResponseFormatException('invalid count');
    expect(error, isA<core.ExtendedResponseFormatException>());
    await expectLater(
      legacy.readExtendedList(Stream.value('error:unsupported'), (value) => value),
      throwsA(isA<core.ExtendedResponseFormatException>()),
    );
    expect(legacy.parseCapabilityEntry('pm', 'cap:pm:hibernate-for <duration>'),
        core.parseCapabilityEntry('pm', 'cap:pm:hibernate-for <duration>'));
  });
}
