import 'dart:async';
import 'dart:io';
import 'dart:typed_data';


class WakeOnLanSettings {
  String macAddress = '';
  String broadcastAddress = '';
  String port = '9';

  String effectiveBroadcastAddress(String baseUrl) {
    return effectiveWakeOnLanBroadcastAddress(
      configuredAddress: broadcastAddress,
      baseUrl: baseUrl,
    );
  }

  int get effectivePort => effectiveWakeOnLanPort(port);

  Future<String> send({
    required String macAddress,
    required String broadcastAddress,
    required String port,
    required String baseUrl,
  }) async {
    final normalizedMac = macAddress.trim();
    if (normalizedMac.isEmpty) {
      return 'Enter a Wake-on-LAN MAC address first.';
    }

    final macBytes = parseWakeOnLanMacAddress(normalizedMac);
    if (macBytes == null) {
      return 'Wake-on-LAN MAC addresses must look like AA:BB:CC:DD:EE:FF.';
    }

    final trimmedBroadcast = broadcastAddress.trim();
    final targetAddress = trimmedBroadcast.isNotEmpty
        ? trimmedBroadcast
        : effectiveBroadcastAddress(baseUrl);
    final parsedAddress = InternetAddress.tryParse(targetAddress);
    if (parsedAddress == null ||
        parsedAddress.type != InternetAddressType.IPv4) {
      return 'Wake-on-LAN requires a valid IPv4 broadcast address.';
    }

    final trimmedPort = port.trim();
    final parsedPort = trimmedPort.isEmpty ? 9 : int.tryParse(trimmedPort);
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      return 'Wake-on-LAN UDP port must be between 1 and 65535.';
    }

    final packet = buildWakeOnLanPacket(macBytes);
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      for (var attempt = 0; attempt < 3; attempt++) {
        socket.send(packet, parsedAddress, parsedPort);
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }
      return 'Wake-on-LAN packet sent to ${parsedAddress.address}:$parsedPort.';
    } on SocketException {
      return 'Couldn\'t send the Wake-on-LAN packet right now.';
    } finally {
      socket?.close();
    }
  }
}

String effectiveWakeOnLanBroadcastAddress({
  required String configuredAddress,
  required String baseUrl,
}) {
  final configured = configuredAddress.trim();
  if (configured.isNotEmpty) {
    return configured;
  }

  final backendUri = Uri.tryParse(baseUrl.trim());
  final host = backendUri?.host ?? '';
  final octets = host.split('.');
  if (octets.length == 4 &&
      octets.every((part) => int.tryParse(part) != null)) {
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }
  return '255.255.255.255';
}

int effectiveWakeOnLanPort(String configuredPort) {
  final parsed = int.tryParse(configuredPort.trim());
  if (parsed == null || parsed < 1 || parsed > 65535) {
    return 9;
  }
  return parsed;
}

Uint8List? parseWakeOnLanMacAddress(String value) {
  final hex = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  if (hex.length != 12) {
    return null;
  }

  final bytes = Uint8List(6);
  for (var index = 0; index < 6; index++) {
    final byte = int.tryParse(
      hex.substring(index * 2, (index * 2) + 2),
      radix: 16,
    );
    if (byte == null) {
      return null;
    }
    bytes[index] = byte;
  }
  return bytes;
}

Uint8List buildWakeOnLanPacket(Uint8List macBytes) {
  final packet = Uint8List(102);
  for (var index = 0; index < 6; index++) {
    packet[index] = 0xFF;
  }
  for (var offset = 6; offset < packet.length; offset += macBytes.length) {
    packet.setRange(offset, offset + macBytes.length, macBytes);
  }
  return packet;
}
