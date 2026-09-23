/// BLE writes and the shared extended-response channel.
/// All multi-response users must use [withExtendedChannel] too; creating a
/// separate queue would let concurrent consumers steal each other's replies.
library;

export 'src/ble/command_transport.dart'
    show
        sendCommand,
        sendLsExtendedCommand,
        withExtendedChannel,
        ensureExtendedNotify,
        verifyExtendedNotify,
        extendedResponseTimeout;
