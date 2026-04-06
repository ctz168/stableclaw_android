import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../constants.dart';
import '../models/setup_state.dart';
import '../models/optional_package.dart';
import '../providers/setup_provider.dart';
import '../services/package_service.dart';
import '../widgets/progress_step.dart';
import 'onboarding_screen.dart';
import 'package_install_screen.dart';

class SetupWizardScreen extends StatefulWidget {
  /// When true, the setup was already complete and we are in "repair/reinstall" mode.
  /// Each step will show a reinstall button instead of just a checkmark.
  final bool isReinstallMode;

  const SetupWizardScreen({super.key, this.isReinstallMode = false});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  bool _started = false;
  Map<String, bool> _pkgStatuses = {};

  /// Track which single step is currently being reinstalled.
  SetupStep? _reinstallingStep;

  bool get _isReinstallMode => widget.isReinstallMode;

  Future<void> _refreshPkgStatuses() async {
    final statuses = await PackageService.checkAllStatuses();
    if (mounted) setState(() => _pkgStatuses = statuses);
  }

  Future<void> _installPackage(OptionalPackage package) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PackageInstallScreen(package: package),
      ),
    );
    if (result == true) _refreshPkgStatuses();
  }

  /// Run a single step for reinstall.
  void _reinstallStep(SetupProvider provider, SetupStep step) {
    if (provider.isRunning) return;
    setState(() {
      _reinstallingStep = step;
      _started = true;
    });
    provider.runSingleStep(step).then((_) {
      if (mounted) {
        setState(() {
          _reinstallingStep = null;
          _started = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: _isReinstallMode
          ? AppBar(title: const Text('Reinstall Steps'))
          : null,
      body: SafeArea(
        child: Consumer<SetupProvider>(
          builder: (context, provider, _) {
            final state = provider.state;

            // Load package statuses once setup completes
            if (state.isComplete && _pkgStatuses.isEmpty) {
              _refreshPkgStatuses();
            }

            // In reinstall mode, if a single step just completed, reset UI
            if (_isReinstallMode && !provider.isRunning && _started) {
              // Single step finished
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isReinstallMode) ...[
                    const SizedBox(height: 32),
                    Image.asset(
                      'assets/ic_launcher.png',
                      width: 64,
                      height: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Setup StableClaw',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _started
                          ? 'Setting up the environment. This may take several minutes.'
                          : 'This will download Ubuntu, Node.js, and StableClaw into a self-contained environment.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Text(
                      'Each step can be reinstalled independently.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 24),
                  Expanded(
                    child: _buildSteps(state, theme, isDark, provider),
                  ),
                  if (state.hasError && !_isReinstallMode) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: theme.colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  state.error ?? 'Unknown error',
                                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.isComplete && !_isReinstallMode)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _goToOnboarding(context),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Configure API Keys'),
                      ),
                    )
                  else if (!_isReinstallMode && (!_started || state.hasError))
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: provider.isRunning
                            ? null
                            : () {
                                setState(() => _started = true);
                                provider.runSetup();
                              },
                        icon: const Icon(Icons.download),
                        label: Text(_started ? 'Retry Setup' : 'Begin Setup'),
                      ),
                    ),
                  if (!_started && !_isReinstallMode) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Requires ~500MB of storage and an internet connection',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'by ${AppConstants.authorName} | ${AppConstants.orgName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSteps(SetupState state, ThemeData theme, bool isDark, SetupProvider provider) {
    final steps = <(int, String, SetupStep, String)>[
      (1, 'Download Ubuntu rootfs', SetupStep.downloadingRootfs, 'Downloads the Ubuntu base filesystem (~80MB)'),
      (2, 'Extract rootfs', SetupStep.extractingRootfs, 'Extracts the Ubuntu filesystem into the environment'),
      (3, 'Install Node.js', SetupStep.installingNode, 'Installs Node.js runtime, npm, and build tools'),
      (4, 'Install StableClaw', SetupStep.installingStableClaw, 'Installs the StableClaw AI gateway via npm'),
      (5, 'Configure Bionic Bypass', SetupStep.configuringBypass, 'Configures the proot compatibility layer'),
    ];

    // Determine the currently active step during single-step reinstall
    final activeStep = provider.isRunningSingleStep ? _reinstallingStep : null;

    return ListView(
      children: [
        for (final (num, label, step, description) in steps)
          _buildStepTile(
            state, theme, isDark, provider,
            stepNumber: num,
            label: label,
            step: step,
            description: description,
            isActive: activeStep == step || (!provider.isRunningSingleStep && state.step == step),
            isComplete: state.stepNumber > step.index || state.isComplete,
            hasError: state.hasError && state.step == step,
            progress: (activeStep == step || (!provider.isRunningSingleStep && state.step == step))
                ? state.progress : null,
          ),
        if (state.isComplete) ...[
          const ProgressStep(
            stepNumber: 6,
            label: 'Setup complete!',
            isComplete: true,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'OPTIONAL PACKAGES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final pkg in OptionalPackage.all)
            _buildPackageTile(theme, pkg, isDark),
        ],
      ],
    );
  }

  Widget _buildStepTile(
    SetupState state,
    ThemeData theme,
    bool isDark,
    SetupProvider provider, {
    required int stepNumber,
    required String label,
    required SetupStep step,
    required String description,
    required bool isActive,
    required bool isComplete,
    required bool hasError,
    double? progress,
  }) {
    // In reinstall mode, show a reinstall button on each step
    if (_isReinstallMode && !provider.isRunning) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.statusGreen,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _reinstallStep(provider, step),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reinstall'),
              ),
            ],
          ),
        ),
      );
    }

    // During a single-step reinstall, show progress
    if (_isReinstallMode && provider.isRunning) {
      final isThisStepActive = _reinstallingStep == step;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isThisStepActive
                    ? theme.colorScheme.primary
                    : AppColors.statusGreen,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: isThisStepActive
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isThisStepActive ? (state.message.isNotEmpty ? state.message : label) : label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isThisStepActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (isThisStepActive && progress != null && progress > 0) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Normal setup mode (first-time setup) — use ProgressStep widget
    return ProgressStep(
      stepNumber: stepNumber,
      label: isActive ? state.message : label,
      isActive: isActive,
      isComplete: isComplete,
      hasError: hasError,
      progress: progress,
    );
  }

  Widget _buildPackageTile(ThemeData theme, OptionalPackage package, bool isDark) {
    final installed = _pkgStatuses[package.id] ?? false;
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(package.icon, color: theme.colorScheme.onSurfaceVariant, size: 22),
        ),
        title: Row(
          children: [
            Text(package.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (installed) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.statusGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Installed',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.statusGreen,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ],
          ],
        ),
        subtitle: Text('${package.description} (${package.estimatedSize})'),
        trailing: installed
            ? const Icon(Icons.check_circle, color: AppColors.statusGreen)
            : OutlinedButton(
                onPressed: () => _installPackage(package),
                child: const Text('Install'),
              ),
      ),
    );
  }

  void _goToOnboarding(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const OnboardingScreen(isFirstRun: true),
      ),
    );
  }
}
