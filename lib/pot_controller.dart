import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bt_link.dart';

/// Dibçəyin Arduino proqramındakı komandalar.
class Cmd {
  static const rfid = '1';
  static const fanOn = '2';
  static const fanOff = '3';
  static const revoke = '4';
  static const dhtToggle = '5';
  static const pumpOn = '6';
  static const pumpOff = '7';
  static const passwordEnd = '#';
}

enum LogDir { rx, tx, info, error }

class LogLine {
  final DateTime time;
  final LogDir dir;
  final String text;
  LogLine(this.dir, this.text) : time = DateTime.now();
}

enum LineEnding {
  none('Yoxdur', ''),
  lf('\\n (LF)', '\n'),
  crlf('\\r\\n (CR+LF)', '\r\n');

  final String label;
  final String value;
  const LineEnding(this.label, this.value);
}

class _CallbackSink implements Sink<String> {
  final void Function(String) onData;
  _CallbackSink(this.onData);
  @override
  void add(String data) => onData(data);
  @override
  void close() {}
}

class PotController extends ChangeNotifier {
  static const fanSeconds = 10;
  static const pumpSeconds = 5;
  static const _maxLog = 600;

  BtLink? _link;
  BtLink? get link => _link;
  bool get connected => _link != null;

  final List<LogLine> log = [];
  LineEnding lineEnding = LineEnding.none;

  /// null = bilinmir, true = giriş açıq, false = bağlı
  bool? access;
  bool waitingCard = false;

  bool dhtOn = false;
  double? temperature;
  double? humidity;
  DateTime? sensorTime;

  DateTime? fanUntil;
  DateTime? pumpUntil;

  final List<StreamSubscription> _subs = [];
  final StringBuffer _rx = StringBuffer();
  Timer? _flushTimer;
  Timer? _ticker;

  // ───────────── qoşulma ─────────────

  Future<void> attach(BtLink link) async {
    await detach(silent: true);
    _link = link;
    _subs.add(link.data.listen(_onData));
    _subs.add(link.disconnected.listen((_) {
      _addLog(LogDir.error, 'Bağlantı kəsildi');
      detach(silent: true);
    }));
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _addLog(LogDir.info, '${link.kind} ilə qoşuldu: ${link.name}');
  }

  Future<void> detach({bool silent = false}) async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _ticker?.cancel();
    _flushTimer?.cancel();
    final l = _link;
    _link = null;
    fanUntil = null;
    pumpUntil = null;
    if (l != null) {
      try {
        await l.close();
      } catch (_) {}
      if (!silent) _addLog(LogDir.info, 'Bağlantı bağlandı');
    }
    notifyListeners();
  }

  // ───────────── göndərmə ─────────────

  Future<bool> send(String text, {bool addEnding = true}) async {
    final l = _link;
    if (l == null) {
      _addLog(LogDir.error, 'Qoşulu deyil — "$text" göndərilmədi');
      return false;
    }
    final payload = addEnding ? text + lineEnding.value : text;
    try {
      await l.write(Uint8List.fromList(utf8.encode(payload)));
      _addLog(LogDir.tx, text);
      return true;
    } catch (e) {
      _addLog(LogDir.error, 'Göndərmə xətası: $e');
      return false;
    }
  }

  Future<void> startRfid() async {
    if (await send(Cmd.rfid)) {
      waitingCard = true;
      notifyListeners();
    }
  }

  Future<void> sendPassword(String digits) async {
    if (await send('$digits${Cmd.passwordEnd}')) {
      waitingCard = false;
      notifyListeners();
    }
  }

  Future<void> revoke() async {
    if (await send(Cmd.revoke)) {
      access = false;
      waitingCard = false;
      fanUntil = null;
      pumpUntil = null;
      notifyListeners();
    }
  }

  Future<void> fanOn() async {
    if (await send(Cmd.fanOn)) {
      fanUntil = DateTime.now().add(const Duration(seconds: fanSeconds));
      notifyListeners();
    }
  }

  Future<void> fanOff() async {
    if (await send(Cmd.fanOff)) {
      fanUntil = null;
      notifyListeners();
    }
  }

  Future<void> pumpOn() async {
    if (await send(Cmd.pumpOn)) {
      pumpUntil = DateTime.now().add(const Duration(seconds: pumpSeconds));
      notifyListeners();
    }
  }

  Future<void> pumpOff() async {
    if (await send(Cmd.pumpOff)) {
      pumpUntil = null;
      notifyListeners();
    }
  }

  Future<void> toggleDht() async {
    if (await send(Cmd.dhtToggle)) {
      dhtOn = !dhtOn;
      notifyListeners();
    }
  }

  void setLineEnding(LineEnding e) {
    lineEnding = e;
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  // ───────────── vaxt sayğacları ─────────────

  double fanProgress() => _progress(fanUntil, fanSeconds);
  double pumpProgress() => _progress(pumpUntil, pumpSeconds);
  int fanLeft() => _left(fanUntil);
  int pumpLeft() => _left(pumpUntil);
  bool get fanRunning => fanUntil != null;
  bool get pumpRunning => pumpUntil != null;

  double _progress(DateTime? until, int total) {
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    return (ms / (total * 1000)).clamp(0.0, 1.0);
  }

  int _left(DateTime? until) {
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _tick() {
    final now = DateTime.now();
    if (fanUntil != null && now.isAfter(fanUntil!)) fanUntil = null;
    if (pumpUntil != null && now.isAfter(pumpUntil!)) pumpUntil = null;
    if (fanRunning || pumpRunning) notifyListeners();
  }

  // ───────────── qəbul ─────────────

  // Çox baytlı hərflər (ə, ş, ı) paketlər arasında bölünə bilər — axınla deşifrə edirik.
  late final ByteConversionSink _decoder = const Utf8Decoder(allowMalformed: true)
      .startChunkedConversion(StringConversionSink.from(_CallbackSink(_onText)));

  void _onData(Uint8List bytes) => _decoder.add(bytes);

  void _onText(String text) {
    for (final ch in text.split('')) {
      if (ch == '\n') {
        _flushLine();
      } else if (ch != '\r') {
        _rx.write(ch);
      }
    }
    // Sətir sonu gəlməsə də bir az sonra göstər
    _flushTimer?.cancel();
    if (_rx.isNotEmpty) {
      _flushTimer = Timer(const Duration(milliseconds: 150), _flushLine);
    }
  }

  void _flushLine() {
    final line = _rx.toString();
    _rx.clear();
    if (line.trim().isEmpty) return;
    _parse(line);
    _addLog(LogDir.rx, line);
  }

  static final _tempRe = RegExp(
      r'(?:\btemp\w*|\btemperatur\w*|\bt)\s*[:=]\s*(-?\d+(?:[.,]\d+)?)',
      caseSensitive: false,
      unicode: true);
  static final _tempUnitRe = RegExp(r'(-?\d+(?:[.,]\d+)?)\s*°?\s*C\b');
  static final _humRe = RegExp(
      r'(?:\bhum\w*|\brütub\w*|\brutub\w*|\bnem\w*|\bh)\s*[:=]\s*(\d+(?:[.,]\d+)?)',
      caseSensitive: false,
      unicode: true);
  static final _humUnitRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*%');

  double? _num(RegExpMatch? m) => m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));

  void _parse(String line) {
    final t = _num(_tempRe.firstMatch(line)) ?? _num(_tempUnitRe.firstMatch(line));
    final h = _num(_humRe.firstMatch(line)) ?? _num(_humUnitRe.firstMatch(line));
    if (t != null || h != null) {
      if (t != null) temperature = t;
      if (h != null) humidity = h;
      sensorTime = DateTime.now();
      dhtOn = true;
    }

    final l = line.toLowerCase();
    const deny = ['yanlış', 'yanlis', 'wrong', 'denied', 'rədd', 'redd', 'ləğv', 'legv',
      'bağlı', 'bagli', 'icazə yox', 'icaze yox'];
    const grant = ['icazə veril', 'icaze veril', 'granted', 'doğru', 'dogru', 'qəbul', 'qebul',
      'unlocked', 'access ok', 'xoş gəldin', 'xos geldin', 'welcome'];
    if (deny.any(l.contains)) {
      access = false;
    } else if (grant.any(l.contains)) {
      access = true;
      waitingCard = false;
    }
  }

  void _addLog(LogDir dir, String text) {
    log.add(LogLine(dir, text));
    if (log.length > _maxLog) log.removeRange(0, log.length - _maxLog);
    notifyListeners();
  }

  @override
  void dispose() {
    detach(silent: true);
    super.dispose();
  }
}
