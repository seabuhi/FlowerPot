import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bt_link.dart';

/// Cihaz seçmə ekranı: BLE skan və cütləşmiş klassik cihazlar.
class ConnectPage extends StatefulWidget {
  final Future<void> Function(BtLink link) onConnected;
  const ConnectPage({super.key, required this.onConnected});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  List<ScanResult> _ble = [];
  List<ClassicDevice> _classic = [];
  bool _scanning = false;
  bool _onlyNamed = true;
  String? _busyId;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(FlutterBluePlus.scanResults.listen((r) {
      if (mounted) setState(() => _ble = r);
    }));
    _subs.add(FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    }));
    _init();
  }

  Future<void> _init() async {
    await _permissions();
    await _loadClassic();
    _scan();
  }

  Future<void> _permissions() async {
    if (!Platform.isAndroid) return;
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<bool> _ensureOn() async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return true;
    try {
      // turnOn() yalnız Android-də var; iOS-da adapterin hazır olmasını gözləyirik
      if (Platform.isAndroid) await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      _toast('Bluetooth-u yandırın');
      return false;
    }
  }

  Future<void> _scan() async {
    if (!await _ensureOn()) return;
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      _toast('Skan xətası: $e');
    }
  }

  Future<void> _loadClassic() async {
    if (!Platform.isAndroid) return; // klassik SPP (HC-05) iOS-da dəstəklənmir
    try {
      final list = await ClassicLink.bondedDevices();
      if (mounted) setState(() => _classic = list);
    } catch (e) {
      _toast('Cütləşmiş cihazlar oxunmadı: $e');
    }
  }

  Future<void> _connect(String id, Future<BtLink> Function() open) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    await FlutterBluePlus.stopScan();
    try {
      final link = await open();
      await widget.onConnected(link);
    } catch (e) {
      _toast('Qoşulmaq alınmadı: ${_short(e)}');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dibçəyə qoşul'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.bluetooth_searching), text: 'BLE (Low Energy)'),
            Tab(icon: Icon(Icons.bluetooth), text: 'Klassik (HC-05)'),
          ]),
        ),
        body: TabBarView(children: [_bleTab(), _classicTab()]),
      ),
    );
  }

  Widget _bleTab() {
    final list = _ble.where((r) => !_onlyNamed || r.device.platformName.isNotEmpty).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Column(children: [
      _hint('HM-10, JDY-08, AT-09, ESP32 BLE kimi modullar. Nordic UART və FFE0/FFE1 '
          'servisləri avtomatik tapılır.'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          FilterChip(
            label: const Text('Yalnız adı olanlar'),
            selected: _onlyNamed,
            onSelected: (v) => setState(() => _onlyNamed = v),
          ),
          const Spacer(),
          _scanning
              ? TextButton.icon(
                  onPressed: FlutterBluePlus.stopScan,
                  icon: const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  label: const Text('Dayandır'))
              : FilledButton.tonalIcon(
                  onPressed: _scan, icon: const Icon(Icons.radar), label: const Text('Axtar')),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? _empty(_scanning ? 'Axtarılır…' : 'Cihaz tapılmadı. "Axtar" düyməsini basın.')
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final r = list[i];
                  final id = r.device.remoteId.str;
                  final name =
                      r.device.platformName.isEmpty ? 'Adsız cihaz' : r.device.platformName;
                  return _deviceTile(
                    icon: Icons.bluetooth_searching,
                    title: name,
                    subtitle: '$id  •  ${r.rssi} dBm',
                    busy: _busyId == id,
                    onTap: () => _connect(id, () => BleLink.connect(r.device)),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _classicTab() {
    return Column(children: [
      _hint('HC-05 / HC-06 / ESP32 BluetoothSerial. Əvvəlcə telefonun Bluetooth ayarlarında '
          'cihazı cütləşdirin (PIN adətən 1234 və ya 0000).'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              await ClassicLink.openSettings();
            },
            icon: const Icon(Icons.settings_bluetooth),
            label: const Text('Cütləşdir'),
          ),
          const Spacer(),
          FilledButton.tonalIcon(
              onPressed: _loadClassic, icon: const Icon(Icons.refresh), label: const Text('Yenilə')),
        ]),
      ),
      Expanded(
        child: _classic.isEmpty
            ? _empty('Cütləşmiş cihaz yoxdur.')
            : ListView.builder(
                itemCount: _classic.length,
                itemBuilder: (_, i) {
                  final d = _classic[i];
                  return _deviceTile(
                    icon: Icons.bluetooth,
                    title: d.name.isEmpty ? 'Adsız cihaz' : d.name,
                    subtitle: d.address,
                    busy: _busyId == d.address,
                    onTap: () => _connect(d.address, () => ClassicLink.connect(d)),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _deviceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Icon(icon, color: cs.onPrimaryContainer)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: busy
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _busyId == null ? onTap : null,
      ),
    );
  }

  Widget _hint(String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
