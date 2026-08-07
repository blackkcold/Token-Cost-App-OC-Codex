import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/relay_models.dart';

class PairScannerView extends StatefulWidget {
  const PairScannerView({super.key});

  @override
  State<PairScannerView> createState() => _PairScannerViewState();
}

class _PairScannerViewState extends State<PairScannerView> {
  late final MobileScannerController _controller;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoZoom: true,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (_processing) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null) return;
    _processing = true;
    try {
      final payload = RelayPairingPayload.parse(value);
      await _controller.stop();
      if (mounted) Navigator.pop(context, payload);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      await Future<void>.delayed(const Duration(seconds: 2));
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描 Mac 配对二维码'),
        actions: [
          IconButton(onPressed: _controller.toggleTorch, icon: const Icon(Icons.flashlight_on), tooltip: '手电筒'),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _detected),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          if (_error != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 42,
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
