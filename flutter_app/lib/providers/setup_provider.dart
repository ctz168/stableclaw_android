import 'package:flutter/foundation.dart';
import '../models/setup_state.dart';
import '../services/bootstrap_service.dart';

class SetupProvider extends ChangeNotifier {
  final BootstrapService _bootstrapService = BootstrapService();
  SetupState _state = const SetupState();
  bool _isRunning = false;
  /// Whether we are running a single step (reinstall mode).
  bool _isRunningSingleStep = false;

  SetupState get state => _state;
  bool get isRunning => _isRunning;
  bool get isRunningSingleStep => _isRunningSingleStep;

  Future<bool> checkIfSetupNeeded() async {
    _state = await _bootstrapService.checkStatus();
    notifyListeners();
    return !_state.isComplete;
  }

  /// Run the full setup from scratch (all steps sequentially).
  Future<void> runSetup() async {
    if (_isRunning) return;
    _isRunning = true;
    _isRunningSingleStep = false;
    notifyListeners();

    await _bootstrapService.runFullSetup(
      onProgress: (state) {
        _state = state;
        notifyListeners();
      },
    );

    _isRunning = false;
    notifyListeners();
  }

  /// Run a single setup step independently (for reinstall/repair).
  /// [targetStep] identifies which step to run.
  Future<void> runSingleStep(SetupStep targetStep) async {
    if (_isRunning) return;
    _isRunning = true;
    _isRunningSingleStep = true;
    notifyListeners();

    final result = await _bootstrapService.runSingleStep(
      targetStep: targetStep,
      onProgress: (state) {
        _state = state;
        notifyListeners();
      },
    );

    // After single step completes, check overall bootstrap status
    // to update the state to show all steps properly.
    if (result.isComplete || !result.hasError) {
      final overallStatus = await _bootstrapService.checkStatus();
      if (overallStatus.isComplete) {
        _state = overallStatus;
      }
    }

    _isRunning = false;
    _isRunningSingleStep = false;
    notifyListeners();
  }

  void reset() {
    _state = const SetupState();
    _isRunning = false;
    _isRunningSingleStep = false;
    notifyListeners();
  }
}
