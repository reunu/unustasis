enum OtaTransferState {
  idle,
  hashing,
  handshaking,
  transferring,
  verifying,
  installing,
  pendingReboot,
  success,
  failure,
}

enum UpdatePlanPhase {
  idle,
  queryingVersions,
  fetchingIndex,
  ready,
  upToDate,
  error
}

/// Presentation policy stays in the application; HTTP codes remain structured.
class UpdateHttpError implements Exception {
  const UpdateHttpError(this.statusCode, {required this.index});
  final int statusCode;
  final bool index;
  @override
  String toString() =>
      '${index ? "Index" : "Download"} failed (HTTP $statusCode)';
}

class UpdateCheckError implements Exception {
  const UpdateCheckError(this.cause);
  final Object cause;
  @override
  String toString() => cause.toString();
}
