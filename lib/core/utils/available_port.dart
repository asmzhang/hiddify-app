import 'dart:io';

/// Return [preferredPort] when loopback can bind it, otherwise ask the OS for
/// an ephemeral loopback port. Windows excluded port ranges are not visible in
/// netstat but still throw [SocketException], so an actual bind is the only
/// reliable check.
Future<int> selectAvailableLoopbackPort(int preferredPort) async {
  ServerSocket? probe;
  try {
    probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, preferredPort);
    return probe.port;
  } on SocketException {
    probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return probe.port;
  } finally {
    await probe?.close();
  }
}
