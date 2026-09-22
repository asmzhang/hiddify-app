const String fallbackObscuredAddress = "*.*.*.*";

String obscureIp(String ip) {
  try {
    if (ip.contains(".")) {
      final splits = ip.split(".");
      return "${splits.first}.*.*.${splits.last}";
    } else if (ip.contains(":")) {
      final splits = ip.split(":");
      return [splits.first, ...splits.sublist(1).map((part) => "*" * part.length)].join(":");
    }
    // Obscure-only formatter: any unexpected input shape falls through to the
    // masked placeholder below; nothing here is worth crashing over.
    // ignore: empty_catches
  } catch (e) {}
  return fallbackObscuredAddress;
}
