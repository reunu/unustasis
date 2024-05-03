import 'dart:developer';

int? convertUint32ToInt(List<int> uint32data) {
  log("Converting $uint32data to int.");
  if (uint32data.length != 4) {
    log("Received empty data for uint32 conversion. Ignoring.");
    return null;
  }

  // Little-endian to big-endian interpretation (important for proper UInt32 conversion)
  return (uint32data[3] << 24) +
      (uint32data[2] << 16) +
      (uint32data[1] << 8) +
      uint32data[0];
}
