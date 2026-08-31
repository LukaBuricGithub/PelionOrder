/// The venue server encodes booleans as the Croatian single letters
/// `"D"` (Da = yes/true) and `"N"` (Ne = no/false). These helpers convert
/// between that wire encoding and Dart [bool], matching the reference client's
/// `String.mapToBoolean()`.
bool croatianStringToBool(Object? value) {
  final s = (value ?? '').toString().trim().toUpperCase();
  return s == 'D';
}

/// Inverse of [croatianStringToBool] — for the rare case the app needs to send
/// a boolean back in the server's `"D"/"N"` form.
String boolToCroatianString(bool value) => value ? 'D' : 'N';
