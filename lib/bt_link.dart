import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Ümumi seriya kanalı: həm BLE, həm də klassik Bluetooth eyni interfeysdən istifadə edir.
abstract class BtLink {
  String get name;
  String get kind; // "BLE" və ya "Klassik"
  Stream<Uint8List> get data;
  Stream<void> get disconnected;
  Future<void> write(Uint8List bytes);
  Future<void> close();
}

// ─────────────────────────── Klassik Bluetooth (SPP) ───────────────────────────

class ClassicDevice {
  final String name;
  final String address;
  ClassicDevice(this.name, this.address);
}

class ClassicLink implements BtLink {
  static const _ch = MethodChannel('agilli_dibcek/classic');
  static const _ev = EventChannel('agilli_dibcek/classic_events');

  static Stream<dynamic>? _events;
  static Stream<dynamic> get _eventStream => _events ??= _ev.receiveBroadcastStream();

  @override
  final String name;
  @override
  String get kind => 'Klassik';

  final _data = StreamController<Uint8List>.broadcast();
  final _disc = StreamController<void>.broadcast();
  StreamSubscription? _sub;

  ClassicLink._(this.name);

  static Future<List<ClassicDevice>> bondedDevices() async {
    final list = await _ch.invokeListMethod<Map>('bondedDevices') ?? [];
    return list
        .map((m) => ClassicDevice((m['name'] as String?) ?? '', m['address'] as String))
        .toList();
  }

  static Future<void> openSettings() => _ch.invokeMethod('openSettings');

  static Future<ClassicLink> connect(ClassicDevice d) async {
    final link = ClassicLink._(d.name.isEmpty ? d.address : d.name);
    link._sub = _eventStream.listen((e) {
      final m = e as Map;
      if (m['type'] == 'data') {
        link._data.add(m['data'] as Uint8List);
      } else if (m['type'] == 'disconnected') {
        link._disc.add(null);
      }
    });
    try {
      await _ch.invokeMethod('connect', {'address': d.address});
    } catch (e) {
      await link._sub?.cancel();
      rethrow;
    }
    return link;
  }

  @override
  Stream<Uint8List> get data => _data.stream;
  @override
  Stream<void> get disconnected => _disc.stream;

  @override
  Future<void> write(Uint8List bytes) => _ch.invokeMethod('write', {'data': bytes});

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _ch.invokeMethod('disconnect');
  }
}

// ─────────────────────────── Bluetooth Low Energy ───────────────────────────

class BleLink implements BtLink {
  /// Məşhur BLE-UART servisləri: Nordic UART (ESP32), HM-10/JDY/AT-09 (FFE0), digər FFF0.
  static final _nusService = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final _nusRx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // telefon → modul
  static final _nusTx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // modul → telefon

  final BluetoothDevice device;
  late BluetoothCharacteristic _writeChar;
  late bool _withoutResponse;
  int _chunk = 20;

  final _data = StreamController<Uint8List>.broadcast();
  final _disc = StreamController<void>.broadcast();
  final List<StreamSubscription> _subs = [];
  bool _closing = false;

  BleLink._(this.device);

  @override
  String get name =>
      device.platformName.isNotEmpty ? device.platformName : device.remoteId.str;
  @override
  String get kind => 'BLE';

  static Future<BleLink> connect(BluetoothDevice device) async {
    final link = BleLink._(device);
    await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
    try {
      await link._setup();
    } catch (e) {
      await device.disconnect();
      rethrow;
    }
    return link;
  }

  Future<void> _setup() async {
    final services = await device.discoverServices();
    BluetoothCharacteristic? writeC;
    BluetoothCharacteristic? notifyC;

    // 1) Nordic UART
    for (final s in services.where((s) => s.uuid == _nusService)) {
      for (final c in s.characteristics) {
        if (c.uuid == _nusRx) writeC = c;
        if (c.uuid == _nusTx) notifyC = c;
      }
    }
    // 2) Digər: notify + write xüsusiyyəti olan ilk xarakteristika (HM-10 FFE1 və s.)
    if (writeC == null || notifyC == null) {
      for (final s in services) {
        final id = s.uuid.str.toLowerCase();
        if (id == '1800' || id == '1801' || id == '180a') continue; // standart servislər
        for (final c in s.characteristics) {
          final p = c.properties;
          if (notifyC == null && (p.notify || p.indicate)) notifyC = c;
          if (writeC == null && (p.write || p.writeWithoutResponse)) writeC = c;
        }
        if (writeC != null && notifyC != null) break;
      }
    }
    if (writeC == null) {
      throw Exception('Bu cihazda yazıla bilən UART xarakteristikası tapılmadı');
    }
    _writeChar = writeC;
    _withoutResponse = writeC.properties.writeWithoutResponse;

    try {
      final mtu = device.mtuNow;
      if (mtu > 23) _chunk = mtu - 3;
    } catch (_) {}

    if (notifyC != null) {
      _subs.add(notifyC.onValueReceived.listen((v) => _data.add(Uint8List.fromList(v))));
      device.cancelWhenDisconnected(_subs.last);
      await notifyC.setNotifyValue(true);
    }
    _subs.add(device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_closing) _disc.add(null);
    }));
  }

  @override
  Stream<Uint8List> get data => _data.stream;
  @override
  Stream<void> get disconnected => _disc.stream;

  @override
  Future<void> write(Uint8List bytes) async {
    for (var i = 0; i < bytes.length; i += _chunk) {
      final end = (i + _chunk < bytes.length) ? i + _chunk : bytes.length;
      await _writeChar.write(bytes.sublist(i, end), withoutResponse: _withoutResponse);
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await device.disconnect();
  }
}
