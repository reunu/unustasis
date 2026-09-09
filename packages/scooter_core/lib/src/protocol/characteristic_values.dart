import 'dart:convert';

String decodeCharacteristicString(List<int> value) {
  var withoutZeros = value.where((element) => element != 0).toList();
  // UTF-8 is a superset of the ASCII the protocol uses; allowMalformed keeps a
  // stray byte from throwing and killing the subscription.
  return utf8.decode(withoutZeros, allowMalformed: true).trim();
}

int? decodeUint32(List<int> data) {
  if (data.length != 4) return null;
  return (data[3] << 24) + (data[2] << 16) + (data[1] << 8) + data[0];
}

int? parseOdometerMeters(List<int> data) {
  if (data.length < 4) return null;
  return decodeUint32(data.sublist(0, 4));
}
