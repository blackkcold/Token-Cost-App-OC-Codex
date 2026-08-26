import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:relay_core/relay_core.dart';

import '../theme/terminal_theme.dart';

class PairScannerPage extends StatefulWidget {
  const PairScannerPage({super.key});

  @override
  State<PairScannerPage> createState() => _PairScannerPageState();
}

class _PairScannerPageState extends State<PairScannerPage> {
  late final MobileScannerController _controller;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_processing) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;
    _processing = true;
    try {
      RelayPairingPayload.parse(rawValue);
      await _controller.stop();
      if (mounted) Navigator.of(context).pop(rawValue);
    } on FormatException {
      if (mounted) {
        setState(
          () => _error = 'The scanned pairing code is invalid or unsupported.',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SCAN PAIRING CODE'),
        backgroundColor: TerminalColors.background,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
            errorBuilder: (context, error) => const _ScannerError(),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: TerminalColors.primary, width: 2),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Color(0x3375F0A7), blurRadius: 24),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: Column(
              children: [
                if (_error != null)
                  _InlineNotice(
                    icon: Icons.error_outline,
                    message: _error!,
                    color: TerminalColors.danger,
                  ),
                const SizedBox(height: 12),
                const _InlineNotice(
                  icon: Icons.lock_outline,
                  message:
                      'The pairing code never changes the configured Relay endpoint.',
                  color: TerminalColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TerminalColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 42),
              const SizedBox(height: 16),
              const Text('CAMERA UNAVAILABLE'),
              const SizedBox(height: 8),
              const Text(
                'Camera access failed. Return and use the manual paste option.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TerminalColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TerminalColors.surface.withValues(alpha: 0.94),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Flexible(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
