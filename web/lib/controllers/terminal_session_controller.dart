import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:relay_core/relay_core.dart';

import '../services/terminal_api.dart';
import '../services/terminal_identity_persistence.dart';

enum TerminalSessionPhase { loading, unpaired, paired, error }

final class TerminalSessionController extends ChangeNotifier {
  TerminalSessionController({
    required this.api,
    required this.store,
    this.autoPoll = true,
  });

  final TerminalApi api;
  final TerminalIdentityPersistence store;
  final bool autoPoll;

  TerminalSessionPhase phase = TerminalSessionPhase.loading;
  RelayIdentity? identity;
  RelayDeviceStatus? deviceStatus;
  String? errorMessage;
  bool busy = false;
  Timer? _pollTimer;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      identity = await store.load();
      phase = identity == null
          ? TerminalSessionPhase.unpaired
          : TerminalSessionPhase.paired;
      notifyListeners();
      if (identity != null) await refreshStatus(silent: true);
    } on Object catch (_) {
      phase = TerminalSessionPhase.error;
      errorMessage = 'Secure browser storage is unavailable.';
      notifyListeners();
    }
  }

  Future<void> pairFromRawValue(String rawValue) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final payload = RelayPairingPayload.parse(rawValue.trim());
      final claimed = await api.claimPairing(payload);
      try {
        await store.save(claimed);
      } on Object catch (_) {
        throw StateError(
          'The browser could not securely save this credential. Do not approve '
          'the pending terminal on the Mac; wait for the pairing code to expire '
          'before retrying.',
        );
      }
      identity = claimed;
      deviceStatus = null;
      phase = TerminalSessionPhase.paired;
      _schedulePoll();
    } on FormatException {
      errorMessage = 'The pairing code is invalid, unsupported, or expired.';
      if (identity == null) phase = TerminalSessionPhase.unpaired;
    } on RelayApiException catch (error) {
      errorMessage = _relayError('Pairing failed', error);
      if (identity == null) phase = TerminalSessionPhase.unpaired;
    } on Object catch (_) {
      errorMessage =
          'Pairing failed because the browser rejected the operation.';
      if (identity == null) phase = TerminalSessionPhase.unpaired;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshStatus({bool silent = false}) async {
    final current = identity;
    if (current == null || busy) return;
    if (!silent) {
      busy = true;
      errorMessage = null;
      notifyListeners();
    }
    try {
      final status = await api.deviceStatus(current);
      if (status.terminal.keyVersion != current.keyVersion) {
        throw const FormatException('Relay returned a mismatched key version');
      }
      final updated = current.copyWith(terminalState: status.terminal.state);
      identity = updated;
      deviceStatus = status;
      phase = TerminalSessionPhase.paired;
      errorMessage = null;
      await store.save(updated);
      _schedulePoll();
    } on RelayApiException catch (error) {
      errorMessage = _relayError('Status sync failed', error);
    } on Object catch (_) {
      errorMessage =
          'Status sync failed because the response could not be verified.';
    } finally {
      if (!silent) busy = false;
      notifyListeners();
    }
  }

  Future<void> revokeTerminal() async {
    final current = identity;
    if (current == null || busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final terminal = await api.revokeTerminal(current);
      final updated = current.copyWith(terminalState: terminal.state);
      identity = updated;
      deviceStatus = null;
      await store.save(updated);
      _pollTimer?.cancel();
    } on RelayApiException catch (error) {
      errorMessage = _relayError('Terminal revocation failed', error);
    } on Object catch (_) {
      errorMessage =
          'Terminal revocation failed because the response could not be verified.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> forgetLocalIdentity() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await store.delete();
      _pollTimer?.cancel();
      identity = null;
      deviceStatus = null;
      errorMessage = null;
      phase = TerminalSessionPhase.unpaired;
    } on Object catch (_) {
      errorMessage = 'Could not clear the browser credential.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (!autoPoll) return;
    final interval = switch (identity?.terminalState) {
      RelayTerminalState.pending => const Duration(seconds: 3),
      RelayTerminalState.active => const Duration(seconds: 30),
      _ => null,
    };
    if (interval == null) return;
    _pollTimer = Timer(interval, () => refreshStatus(silent: true));
  }

  static String _relayError(String fallback, RelayApiException error) =>
      error.code == null ? fallback : '$fallback (${error.code})';

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
