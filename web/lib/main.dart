import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'controllers/terminal_session_controller.dart';
import 'services/relay_endpoint.dart';
import 'services/terminal_api.dart';
import 'services/terminal_identity_store.dart';
import 'theme/terminal_theme.dart';
import 'views/terminal_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    MobileScannerPlatform.instance
      ..setWebBarcodeReader(WebBarcodeReader.zxingJs)
      ..setBarcodeLibraryScriptUrl('barcode/zxing-0.23.0.min.js');
  }

  try {
    final endpoint = RelayEndpoint.requireConfigured();
    final controller = TerminalSessionController(
      api: RelayTerminalApi(endpoint),
      store: createTerminalIdentityStore(endpoint),
    );
    runApp(TokenCostTerminalApp(controller: controller));
  } on StateError catch (error) {
    runApp(TerminalConfigurationErrorApp(message: error.message));
  }
}

class TokenCostTerminalApp extends StatelessWidget {
  const TokenCostTerminalApp({super.key, required this.controller});

  final TerminalSessionController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Token Cost Terminal',
      debugShowCheckedModeBanner: false,
      theme: TerminalTheme.dark,
      home: TerminalHomePage(controller: controller),
    );
  }
}

class TerminalConfigurationErrorApp extends StatelessWidget {
  const TerminalConfigurationErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Token Cost Terminal',
      debugShowCheckedModeBanner: false,
      theme: TerminalTheme.dark,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_ethernet, size: 44),
                  const SizedBox(height: 20),
                  const Text(
                    'RELAY ENDPOINT NOT CONFIGURED',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
