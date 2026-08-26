import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_core/relay_core.dart';

import '../controllers/terminal_session_controller.dart';
import '../theme/terminal_theme.dart';
import 'pair_scanner_page.dart';

class TerminalHomePage extends StatefulWidget {
  const TerminalHomePage({super.key, required this.controller});

  final TerminalSessionController controller;

  @override
  State<TerminalHomePage> createState() => _TerminalHomePageState();
}

class _TerminalHomePageState extends State<TerminalHomePage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
  }

  Future<void> _scan() async {
    final value = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PairScannerPage()));
    if (value != null) await widget.controller.pairFromRawValue(value);
  }

  Future<void> _paste() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PASTE PAIRING LINK'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: input,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'balance-relay://pair?data=...',
              helperText:
                  'Only the pairing payload is read. Relay endpoint fields are rejected.',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('VERIFY & CLAIM'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await widget.controller.pairFromRawValue(value);
    }
  }

  Future<void> _confirmRevoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('REVOKE THIS TERMINAL?'),
        content: const Text(
          'The Relay will reject this browser terminal immediately. Reconnecting requires a new QR code from the Mac.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('REVOKE TERMINAL'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.revokeTerminal();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: _GridBackground()),
              SafeArea(
                child: SelectionArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(controller: controller),
                            const SizedBox(height: 54),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final overview = _OverviewPanel(
                                  state: controller.identity?.terminalState,
                                );
                                final terminal = _TerminalPanel(
                                  controller: controller,
                                  onScan: _scan,
                                  onPaste: _paste,
                                  onRevoke: _confirmRevoke,
                                );
                                if (constraints.maxWidth >= 860) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 5, child: overview),
                                      const SizedBox(width: 28),
                                      Expanded(flex: 6, child: terminal),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    overview,
                                    const SizedBox(height: 24),
                                    terminal,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 28),
                            const _SecurityBoundary(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (controller.busy)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final TerminalSessionController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.identity != null;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            border: Border.all(color: TerminalColors.primary),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.terminal, color: TerminalColors.primary),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOKEN COST / TERMINAL',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'PRIVATE RELAY CONTROL SURFACE',
                style: TextStyle(
                  color: TerminalColors.textMuted,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        _StatusPill(
          label: connected ? 'TERMINAL LOADED' : 'NO TERMINAL',
          color: connected ? TerminalColors.primary : TerminalColors.textMuted,
        ),
      ],
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({required this.state});

  final RelayTerminalState? state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state == null
                ? 'A QUIET WINDOW\nINTO YOUR MAC.'
                : 'ONE DEVICE.\nONE ACTIVE TERMINAL.',
            style: TextStyle(
              fontSize: MediaQuery.sizeOf(context).width < 500 ? 38 : 54,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Pair once. The Relay forwards opaque end-to-end encrypted messages and cannot read the payload.',
            style: TextStyle(
              color: TerminalColors.textMuted,
              fontSize: 16,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 30),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Capability(label: 'AES-256-GCM'),
              _Capability(label: 'KEY VERSION BOUND'),
              _Capability(label: '7 DAY ACTIVITY TTL'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel({
    required this.controller,
    required this.onScan,
    required this.onPaste,
    required this.onRevoke,
  });

  final TerminalSessionController controller;
  final VoidCallback onScan;
  final VoidCallback onPaste;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (controller.phase) {
          TerminalSessionPhase.loading => const _LoadingPanel(),
          TerminalSessionPhase.unpaired => _UnpairedPanel(
            error: controller.errorMessage,
            busy: controller.busy,
            onScan: onScan,
            onPaste: onPaste,
          ),
          TerminalSessionPhase.error => _ErrorPanel(
            message: controller.errorMessage ?? 'Secure storage unavailable.',
          ),
          TerminalSessionPhase.paired => _PairedPanel(
            controller: controller,
            onRevoke: onRevoke,
          ),
        },
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 330,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _UnpairedPanel extends StatelessWidget {
  const _UnpairedPanel({
    required this.error,
    required this.busy,
    required this.onScan,
    required this.onPaste,
  });

  final String? error;
  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelEyebrow(index: '01', label: 'PAIR BROWSER TERMINAL'),
        const SizedBox(height: 28),
        Container(
          height: 190,
          decoration: BoxDecoration(
            color: TerminalColors.raisedSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: TerminalColors.border),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_2, size: 72, color: TerminalColors.primary),
              SizedBox(height: 14),
              Text('SCAN THE CODE SHOWN ON YOUR MAC'),
              SizedBox(height: 5),
              Text(
                'PAIRING WINDOW EXPIRES IN 5 MINUTES',
                style: TextStyle(color: TerminalColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          _ErrorNotice(message: error!),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onScan,
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('OPEN CAMERA'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onPaste,
              icon: const Icon(Icons.content_paste),
              label: const Text('PASTE LINK'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PairedPanel extends StatelessWidget {
  const _PairedPanel({required this.controller, required this.onRevoke});

  final TerminalSessionController controller;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final identity = controller.identity!;
    final state = identity.terminalState;
    final presentation = _statePresentation(state);
    final status = controller.deviceStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelEyebrow(index: '02', label: 'TERMINAL ${state.wireValue}'),
        const SizedBox(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: presentation.color.withValues(alpha: 0.12),
                border: Border.all(
                  color: presentation.color.withValues(alpha: 0.5),
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(presentation.icon, color: presentation.color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    presentation.description,
                    style: const TextStyle(
                      color: TerminalColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _DataRow(label: 'DEVICE', value: _shortId(identity.deviceId)),
        _DataRow(label: 'KEY VERSION', value: identity.keyVersion.toString()),
        _DataRow(
          label: 'MAC LINK',
          value: status == null
              ? 'UNKNOWN'
              : status.online
              ? 'ONLINE'
              : 'OFFLINE',
        ),
        _DataRow(
          label: 'TERMINAL TTL',
          value: _formatTime(status?.terminal.expiresAt),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 16),
          _ErrorNotice(message: controller.errorMessage!),
        ],
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: controller.busy ? null : controller.refreshStatus,
              icon: const Icon(Icons.sync),
              label: const Text('SYNC STATUS'),
            ),
            if (state == RelayTerminalState.pending ||
                state == RelayTerminalState.active)
              OutlinedButton.icon(
                onPressed: controller.busy ? null : onRevoke,
                icon: const Icon(Icons.link_off),
                label: const Text('REVOKE'),
              ),
            if (state != RelayTerminalState.pending &&
                state != RelayTerminalState.active)
              FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : controller.forgetLocalIdentity,
                icon: const Icon(Icons.restart_alt),
                label: const Text('PAIR AGAIN'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => _ErrorNotice(message: message);
}

class _SecurityBoundary extends StatelessWidget {
  const _SecurityBoundary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TerminalColors.surface.withValues(alpha: 0.7),
        border: Border.all(color: TerminalColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.security, color: TerminalColors.primary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'SECURITY BOUNDARY  /  Credentials are encrypted at rest with a non-extractable WebCrypto key in IndexedDB. This reduces casual disk exposure but cannot protect against malicious code running on this same origin.',
              style: TextStyle(
                color: TerminalColors.textMuted,
                fontSize: 12,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = TerminalColors.primary.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 42.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: TerminalColors.raisedSurface,
        border: Border.all(color: TerminalColors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: const TextStyle(color: TerminalColors.textMuted, fontSize: 11),
      ),
    );
  }
}

class _PanelEyebrow extends StatelessWidget {
  const _PanelEyebrow({required this.index, required this.label});

  final String index;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(index, style: const TextStyle(color: TerminalColors.primary)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, letterSpacing: 1.1),
          ),
        ),
      ],
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: TerminalColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: TerminalColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TerminalColors.danger.withValues(alpha: 0.08),
          border: Border.all(
            color: TerminalColors.danger.withValues(alpha: 0.45),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              color: TerminalColors.danger,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

({IconData icon, Color color, String title, String description})
_statePresentation(RelayTerminalState state) => switch (state) {
  RelayTerminalState.pending => (
    icon: Icons.hourglass_top,
    color: TerminalColors.warning,
    title: 'WAITING FOR MAC APPROVAL',
    description:
        'Keep this page open, then approve the pending terminal on your Mac.',
  ),
  RelayTerminalState.active => (
    icon: Icons.verified_user_outlined,
    color: TerminalColors.primary,
    title: 'TERMINAL ACTIVE',
    description:
        'This is the only active terminal for the registered Mac identity.',
  ),
  RelayTerminalState.expired => (
    icon: Icons.timer_off_outlined,
    color: TerminalColors.warning,
    title: 'TERMINAL EXPIRED',
    description:
        'Seven days passed without an accepted user query. Pair again to continue.',
  ),
  RelayTerminalState.revoked => (
    icon: Icons.block,
    color: TerminalColors.danger,
    title: 'TERMINAL REVOKED',
    description: 'The Relay no longer accepts this browser credential.',
  ),
  RelayTerminalState.replaced => (
    icon: Icons.swap_horiz,
    color: TerminalColors.info,
    title: 'TERMINAL REPLACED',
    description: 'A newer terminal was activated for this Mac identity.',
  ),
};

String _shortId(String value) => value.length <= 20
    ? value
    : '${value.substring(0, 10)}...${value.substring(value.length - 6)}';

String _formatTime(int? milliseconds) {
  if (milliseconds == null || milliseconds <= 0) return 'NOT REPORTED';
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
