import 'package:flutter/material.dart';

import 'pot_controller.dart';
import 'terminal_page.dart';

/// Əsas idarə paneli: hər komanda üçün vizual düymə.
class ControlPage extends StatefulWidget {
  final PotController pot;
  const ControlPage({super.key, required this.pot});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  int _tab = 0;

  PotController get pot => widget.pot;

  @override
  Widget build(BuildContext context) {
    final link = pot.link;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ağıllı Dibçək'),
          Text('${link?.kind ?? ''} • ${link?.name ?? ''}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(
            tooltip: 'Ayır',
            icon: const Icon(Icons.bluetooth_disabled),
            onPressed: pot.detach,
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        _Panel(pot: pot),
        TerminalPage(pot: pot),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Panel'),
          NavigationDestination(icon: Icon(Icons.terminal_outlined), selectedIcon: Icon(Icons.terminal), label: 'Terminal'),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final PotController pot;
  const _Panel({required this.pot});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _AccessCard(pot: pot),
        const SizedBox(height: 12),
        _ClimateCard(pot: pot),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _DeviceCard(
              title: 'Fan',
              seconds: PotController.fanSeconds,
              running: pot.fanRunning,
              left: pot.fanLeft(),
              progress: pot.fanProgress(),
              color: Colors.lightBlue,
              icon: (on) => _Spinner(spinning: on, child: const Icon(Icons.toys, size: 44)),
              onCmd: '2',
              offCmd: '3',
              onStart: pot.fanOn,
              onStop: pot.fanOff,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DeviceCard(
              title: 'Su motoru',
              seconds: PotController.pumpSeconds,
              running: pot.pumpRunning,
              left: pot.pumpLeft(),
              progress: pot.pumpProgress(),
              color: Colors.teal,
              icon: (on) => Icon(on ? Icons.water_drop : Icons.water_drop_outlined, size: 44),
              onCmd: '6',
              offCmd: '7',
              onStart: pot.pumpOn,
              onStop: pot.pumpOff,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          'Fan və su motoru yalnız giriş icazəsi olduqda işləyir.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ───────────── Giriş (RFID + şifrə) ─────────────

class _AccessCard extends StatelessWidget {
  final PotController pot;
  const _AccessCard({required this.pot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color color, IconData icon, String label) = switch (pot.access) {
      true => (Colors.green, Icons.lock_open_rounded, 'Giriş açıqdır'),
      false => (Colors.red, Icons.lock_rounded, 'Giriş bağlıdır'),
      null => (cs.outline, Icons.lock_outline_rounded, 'Giriş: naməlum'),
    };

    return Card(
      color: color.withValues(alpha: .12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 16)],
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  pot.waitingCard
                      ? 'Kartı oxudun, sonra şifrəni daxil edin'
                      : 'RFID kart + şifrə ilə giriş',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _CmdButton(
                code: '1',
                icon: Icons.contactless,
                label: 'RFID kart',
                onPressed: () async {
                  await pot.startRfid();
                  if (context.mounted) _openKeypad(context, pot);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CmdButton(
                code: '#',
                icon: Icons.dialpad,
                label: 'Şifrə',
                onPressed: () => _openKeypad(context, pot),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _CmdButton(
            code: '4',
            icon: Icons.block,
            label: 'Girişi ləğv et',
            danger: true,
            onPressed: pot.revoke,
          ),
        ]),
      ),
    );
  }
}

void _openKeypad(BuildContext context, PotController pot) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Keypad(onSubmit: pot.sendPassword),
  );
}

class _Keypad extends StatefulWidget {
  final Future<void> Function(String) onSubmit;
  const _Keypad({required this.onSubmit});

  @override
  State<_Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<_Keypad> {
  String _code = '';
  bool _show = false;

  void _press(String k) => setState(() {
        if (_code.length < 8) _code += k;
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, IconData? icon, Color? bg, Color? fg}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: bg ?? cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap ?? () => _press(label),
            child: SizedBox(
              height: 64,
              child: Center(
                child: icon != null
                    ? Icon(icon, color: fg, size: 28)
                    : Text(label, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: fg)),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Şifrəni daxil edin', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              constraints: const BoxConstraints(minWidth: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _code.isEmpty ? '— — — —' : (_show ? _code : '*' * _code.length),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 30, letterSpacing: 8, fontFamily: 'monospace'),
              ),
            ),
            IconButton(
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
          ]),
          const SizedBox(height: 16),
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
            Row(children: [for (final k in row) Expanded(child: key(k))]),
          Row(children: [
            Expanded(
              child: key('⌫',
                  icon: Icons.backspace_outlined,
                  onTap: () => setState(() {
                        if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1);
                      })),
            ),
            Expanded(child: key('0')),
            Expanded(
              child: key('#',
                  icon: Icons.check_rounded,
                  bg: cs.primary,
                  fg: cs.onPrimary,
                  onTap: _code.isEmpty
                      ? null
                      : () async {
                          final nav = Navigator.of(context);
                          await widget.onSubmit(_code);
                          nav.pop();
                        }),
            ),
          ]),
          const SizedBox(height: 8),
          Text('✓ basıldıqda şifrə və "#" göndərilir',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

// ───────────── Temperatur və rütubət ─────────────

class _ClimateCard extends StatelessWidget {
  final PotController pot;
  const _ClimateCard({required this.pot});

  String _fmt(double? v) => v == null ? '--' : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    final t = pot.sensorTime;
    final ago = t == null
        ? 'Hələ data gəlməyib'
        : 'Son yenilənmə: ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.eco),
            const SizedBox(width: 8),
            Expanded(child: Text('DHT11 sensoru', style: Theme.of(context).textTheme.titleMedium)),
            const _CodeChip('5'),
            Switch(value: pot.dhtOn, onChanged: (_) => pot.toggleDht()),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _Gauge(
                icon: Icons.thermostat,
                label: 'Temperatur',
                value: _fmt(pot.temperature),
                unit: '°C',
                fraction: pot.temperature == null ? 0 : (pot.temperature! / 50).clamp(0, 1),
                color: Colors.deepOrange,
                dim: !pot.dhtOn,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Gauge(
                icon: Icons.water_drop,
                label: 'Rütubət',
                value: _fmt(pot.humidity),
                unit: '%',
                fraction: pot.humidity == null ? 0 : (pot.humidity! / 100).clamp(0, 1),
                color: Colors.blue,
                dim: !pot.dhtOn,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(pot.dhtOn ? ago : 'Göstərmək üçün açarı yandırın (komanda 5)',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  final IconData icon;
  final String label, value, unit;
  final double fraction;
  final Color color;
  final bool dim;
  const _Gauge({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.fraction,
    required this.color,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: dim ? .45 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ]),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            TextSpan(text: ' $unit', style: TextStyle(fontSize: 16, color: color)),
          ])),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: const Duration(milliseconds: 500),
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: .15),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ───────────── Fan / Su motoru ─────────────

class _DeviceCard extends StatelessWidget {
  final String title;
  final int seconds;
  final bool running;
  final int left;
  final double progress;
  final Color color;
  final Widget Function(bool on) icon;
  final String onCmd, offCmd;
  final VoidCallback onStart, onStop;

  const _DeviceCard({
    required this.title,
    required this.seconds,
    required this.running,
    required this.left,
    required this.progress,
    required this.color,
    required this.icon,
    required this.onCmd,
    required this.offCmd,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: running ? color.withValues(alpha: .15) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: running ? progress : 0,
                  strokeWidth: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: .15),
                ),
              ),
              IconTheme(data: IconThemeData(color: running ? color : Colors.grey), child: icon(running)),
            ]),
          ),
          const SizedBox(height: 6),
          Text(running ? '$left san qaldı' : 'Sönülü',
              style: TextStyle(color: running ? color : null, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _CmdButton(code: onCmd, icon: Icons.play_arrow_rounded, label: '$seconds san', onPressed: onStart),
          const SizedBox(height: 6),
          _CmdButton(code: offCmd, icon: Icons.stop_rounded, label: 'Dayandır', danger: true, onPressed: onStop),
        ]),
      ),
    );
  }
}

class _Spinner extends StatefulWidget {
  final bool spinning;
  final Widget child;
  const _Spinner({required this.spinning, required this.child});

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _c.repeat();
  }

  @override
  void didUpdateWidget(_Spinner old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_c.isAnimating) _c.repeat();
    if (!widget.spinning && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}

// ───────────── ümumi düymələr ─────────────

class _CmdButton extends StatelessWidget {
  final String code;
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onPressed;
  const _CmdButton({
    required this.code,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      backgroundColor: danger ? cs.errorContainer : cs.primary,
      foregroundColor: danger ? cs.onErrorContainer : cs.onPrimary,
      minimumSize: const Size.fromHeight(46),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return FilledButton(
      style: style,
      onPressed: onPressed,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 20),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String code;
  const _CodeChip(this.code);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      );
}
