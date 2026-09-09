import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/service/ble_commands.dart';

import '../support/command_transport_fakes.dart';

void main() {
  testWidgets('silent and closed response streams time out and release the queue', (tester) async {
    // Cancellation can return an already completed future owned by the real
    // zone. Drain that zone too, without advancing the fake response clock.
    Future<void> flush() async {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    for (final closeSource in [false, true]) {
      final device = TransportTestDevice();
      final command = TransportTestCharacteristic();
      final response = TransportTestCharacteristic();
      final replacement = TransportTestCharacteristic();
      final repo = CharacteristicRepository(device)
        ..extendedCommandCharacteristic = command
        ..extendedResponseCharacteristic = response;
      var completed = false;
      final first = sendLsExtendedCommand(device, repo, 'silent').then((value) {
        completed = true;
        return value;
      });
      final timedOut = expectLater(first, completion(isNull));
      final next = expectLater(sendLsExtendedCommand(device, repo, 'next'), completion('next:ok'));
      await flush();
      expect(command.writes.map((write) => write.command), ['silent']);
      expect(response.listeners, 1);
      if (closeSource) {
        // Source closure is not forwarded by the existing response buffer.
        final closed = response.values.close();
        await flush();
        await closed;
        repo.extendedResponseCharacteristic = replacement;
      }
      await tester.pump(const Duration(milliseconds: 9999));
      await flush();
      expect(completed, isFalse);
      expect(command.writes, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      await flush();
      await timedOut;
      expect(completed, isTrue);
      expect(response.cancellations, 1);
      expect(command.writes.map((write) => write.command), ['silent', 'next']);
      final nextResponse = closeSource ? replacement : response;
      expect(nextResponse.listeners, 1);
      nextResponse.reply('next:ok');
      await flush();
      await next;
      expect(nextResponse.listeners, 0);
      expect(response.maxListeners, 1);
      final closed = Future.wait([command.values.close(), response.values.close(), replacement.values.close()]);
      await flush();
      await closed;
    }
  });
}
