import 'dart:io';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../models/setup_state.dart';
import 'native_bridge.dart';

class BootstrapService {
  final Dio _dio = Dio();

  void _updateSetupNotification(String text, {int progress = -1}) {
    try {
      NativeBridge.updateSetupNotification(text, progress: progress);
    } catch (_) {}
  }

  void _stopSetupService() {
    try {
      NativeBridge.stopSetupService();
    } catch (_) {}
  }

  Future<void> _startSetupService() async {
    try {
      await NativeBridge.startSetupService();
    } catch (_) {}
  }

  Future<SetupState> checkStatus() async {
    try {
      final complete = await NativeBridge.isBootstrapComplete();
      if (complete) {
        return const SetupState(
          step: SetupStep.complete,
          progress: 1.0,
          message: 'Setup complete',
        );
      }
      return const SetupState(
        step: SetupStep.checkingStatus,
        progress: 0.0,
        message: 'Setup required',
      );
    } catch (e) {
      return SetupState(
        step: SetupStep.error,
        error: 'Failed to check status: $e',
      );
    }
  }

  // ──────────────────────────────────────────────
  // Individual step methods (can be run independently)
  // ──────────────────────────────────────────────

  /// Step 0: Setup directories + DNS resolv.conf
  Future<void> runStepSetupDirs({
    required void Function(SetupState) onProgress,
  }) async {
    onProgress(const SetupState(
      step: SetupStep.checkingStatus,
      progress: 0.5,
      message: 'Setting up directories...',
    ));
    _updateSetupNotification('Setting up directories...', progress: 2);
    try { await NativeBridge.setupDirs(); } catch (_) {}
    try { await NativeBridge.writeResolv(); } catch (_) {}

    // Direct Dart fallback: ensure config dir + resolv.conf exist.
    const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';
    try {
      final filesDir = await NativeBridge.getFilesDir();
      final configDir = '$filesDir/config';
      final resolvFile = File('$configDir/resolv.conf');
      if (!resolvFile.existsSync()) {
        Directory(configDir).createSync(recursive: true);
        resolvFile.writeAsStringSync(resolvContent);
      }
      final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
      if (!rootfsResolv.existsSync()) {
        rootfsResolv.parent.createSync(recursive: true);
        rootfsResolv.writeAsStringSync(resolvContent);
      }
    } catch (_) {}
  }

  /// Step 1: Download Ubuntu rootfs
  Future<void> runStepDownloadRootfs({
    required void Function(SetupState) onProgress,
  }) async {
    final arch = await NativeBridge.getArch();
    final rootfsUrl = AppConstants.getRootfsUrl(arch);
    final filesDir = await NativeBridge.getFilesDir();
    final tarPath = '$filesDir/tmp/ubuntu-rootfs.tar.gz';

    _updateSetupNotification('Downloading Ubuntu rootfs...', progress: 5);
    onProgress(const SetupState(
      step: SetupStep.downloadingRootfs,
      progress: 0.0,
      message: 'Downloading Ubuntu rootfs...',
    ));

    await _dio.download(
      rootfsUrl,
      tarPath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final progress = received / total;
          final mb = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
          final notifProgress = 5 + (progress * 25).round();
          _updateSetupNotification('Downloading rootfs: $mb / $totalMb MB', progress: notifProgress);
          onProgress(SetupState(
            step: SetupStep.downloadingRootfs,
            progress: progress,
            message: 'Downloading: $mb MB / $totalMb MB',
          ));
        }
      },
    );

    onProgress(const SetupState(
      step: SetupStep.downloadingRootfs,
      progress: 1.0,
      message: 'Rootfs downloaded',
    ));
  }

  /// Step 2: Extract rootfs
  Future<void> runStepExtractRootfs({
    required void Function(SetupState) onProgress,
  }) async {
    final filesDir = await NativeBridge.getFilesDir();
    final tarPath = '$filesDir/tmp/ubuntu-rootfs.tar.gz';

    _updateSetupNotification('Extracting rootfs...', progress: 30);
    onProgress(const SetupState(
      step: SetupStep.extractingRootfs,
      progress: 0.0,
      message: 'Extracting rootfs (this takes a while)...',
    ));
    await NativeBridge.extractRootfs(tarPath);
    onProgress(const SetupState(
      step: SetupStep.extractingRootfs,
      progress: 1.0,
      message: 'Rootfs extracted',
    ));
  }

  /// Step 3: Install Node.js (fix permissions, apt, download+extract Node.js)
  Future<void> runStepInstallNode({
    required void Function(SetupState) onProgress,
  }) async {
    // Install bionic bypass + cwd-fix + node-wrapper BEFORE using node.
    await NativeBridge.installBionicBypass();

    // Fix permissions inside proot
    _updateSetupNotification('Fixing rootfs permissions...', progress: 45);
    onProgress(const SetupState(
      step: SetupStep.installingNode,
      progress: 0.0,
      message: 'Fixing rootfs permissions...',
    ));
    await NativeBridge.runInProot(
      'chmod -R 755 /usr/bin /usr/sbin /bin /sbin '
      '/usr/local/bin /usr/local/sbin 2>/dev/null; '
      'chmod -R +x /usr/lib/apt/ /usr/lib/dpkg/ /usr/libexec/ '
      '/var/lib/dpkg/info/ /usr/share/debconf/ 2>/dev/null; '
      'chmod 755 /lib/*/ld-linux-*.so* /usr/lib/*/ld-linux-*.so* 2>/dev/null; '
      'mkdir -p /var/lib/dpkg/updates /var/lib/dpkg/triggers; '
      'echo permissions_fixed',
    );

    // Install base packages via apt-get
    _updateSetupNotification('Updating package lists...', progress: 48);
    onProgress(const SetupState(
      step: SetupStep.installingNode,
      progress: 0.1,
      message: 'Updating package lists...',
    ));
    await NativeBridge.runInProot('apt-get update -y');

    _updateSetupNotification('Installing base packages...', progress: 52);
    onProgress(const SetupState(
      step: SetupStep.installingNode,
      progress: 0.15,
      message: 'Installing base packages...',
    ));
    await NativeBridge.runInProot(
      'ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime && '
      'echo "Etc/UTC" > /etc/timezone',
    );
    await NativeBridge.runInProot(
      'apt-get install -y --no-install-recommends '
      'ca-certificates git python3 make g++ curl wget',
    );

    // Download Node.js binary tarball
    final arch = await NativeBridge.getArch();
    final nodeTarUrl = AppConstants.getNodeTarballUrl(arch);
    final filesDir = await NativeBridge.getFilesDir();
    final nodeTarPath = '$filesDir/tmp/nodejs.tar.xz';

    onProgress(const SetupState(
      step: SetupStep.installingNode,
      progress: 0.3,
      message: 'Downloading Node.js ${AppConstants.nodeVersion}...',
    ));
    _updateSetupNotification('Downloading Node.js...', progress: 55);
    await _dio.download(
      nodeTarUrl,
      nodeTarPath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final progress = 0.3 + (received / total) * 0.4;
          final mb = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
          final notifProgress = 55 + ((received / total) * 15).round();
          _updateSetupNotification('Downloading Node.js: $mb / $totalMb MB', progress: notifProgress);
          onProgress(SetupState(
            step: SetupStep.installingNode,
            progress: progress,
            message: 'Downloading Node.js: $mb MB / $totalMb MB',
          ));
        }
      },
    );

    _updateSetupNotification('Extracting Node.js...', progress: 72);
    onProgress(const SetupState(
      step: SetupStep.installingNode,
      progress: 0.75,
      message: 'Extracting Node.js...',
    ));
    await NativeBridge.extractNodeTarball(nodeTarPath);

    _updateSetupNotification('Verifying Node.js...', progress: 78);
    onProgress(const SetupState(
      step: SetupStep.installingNode,
      progress: 0.9,
      message: 'Verifying Node.js...',
    ));
    const wrapper = '/root/.stableclaw/node-wrapper.js';
    const nodeRun = 'node $wrapper';
    const npmCli = '/usr/local/lib/node_modules/npm/bin/npm-cli.js';
    await NativeBridge.runInProot(
      'node --version && $nodeRun $npmCli --version',
    );
    onProgress(const SetupState(
      step: SetupStep.installingNode,
      progress: 1.0,
      message: 'Node.js installed',
    ));
  }

  /// Step 4: Install StableClaw via npm
  Future<void> runStepInstallStableClaw({
    required void Function(SetupState) onProgress,
  }) async {
    _updateSetupNotification('Installing StableClaw...', progress: 82);
    onProgress(const SetupState(
      step: SetupStep.installingStableClaw,
      progress: 0.0,
      message: 'Installing StableClaw (this may take a few minutes)...',
    ));

    const wrapper = '/root/.stableclaw/node-wrapper.js';
    const nodeRun = 'node $wrapper';
    const npmCli = '/usr/local/lib/node_modules/npm/bin/npm-cli.js';

    await NativeBridge.runInProot(
      '$nodeRun $npmCli install -g stableclaw',
      timeout: 1800,
    );

    _updateSetupNotification('Creating bin wrappers...', progress: 92);
    onProgress(const SetupState(
      step: SetupStep.installingStableClaw,
      progress: 0.7,
      message: 'Creating bin wrappers...',
    ));
    await NativeBridge.createBinWrappers('stableclaw');

    _updateSetupNotification('Verifying StableClaw...', progress: 96);
    onProgress(const SetupState(
      step: SetupStep.installingStableClaw,
      progress: 0.9,
      message: 'Verifying StableClaw...',
    ));
    await NativeBridge.runInProot('stableclaw --version || echo stableclaw_installed');
    onProgress(const SetupState(
      step: SetupStep.installingStableClaw,
      progress: 1.0,
      message: 'StableClaw installed',
    ));
  }

  /// Step 5: Configure Bionic Bypass
  Future<void> runStepConfigureBypass({
    required void Function(SetupState) onProgress,
  }) async {
    _updateSetupNotification('Configuring bypass...', progress: 99);
    onProgress(const SetupState(
      step: SetupStep.configuringBypass,
      progress: 0.5,
      message: 'Configuring Bionic Bypass...',
    ));
    await NativeBridge.installBionicBypass();
    onProgress(const SetupState(
      step: SetupStep.configuringBypass,
      progress: 1.0,
      message: 'Bionic Bypass configured',
    ));
  }

  // ──────────────────────────────────────────────
  // Run a single step by enum
  // ──────────────────────────────────────────────

  /// Run a single setup step identified by [targetStep].
  /// Returns the final state after the step completes.
  Future<SetupState> runSingleStep({
    required SetupStep targetStep,
    required void Function(SetupState) onProgress,
  }) async {
    try {
      await _startSetupService();
      await runStepSetupDirs(onProgress: onProgress);

      switch (targetStep) {
        case SetupStep.downloadingRootfs:
          await runStepDownloadRootfs(onProgress: onProgress);
          _stopSetupService();
          return SetupState(
            step: SetupStep.complete,
            progress: 1.0,
            message: 'Rootfs download complete',
          );
        case SetupStep.extractingRootfs:
          await runStepExtractRootfs(onProgress: onProgress);
          _stopSetupService();
          return SetupState(
            step: SetupStep.complete,
            progress: 1.0,
            message: 'Rootfs extraction complete',
          );
        case SetupStep.installingNode:
          await runStepInstallNode(onProgress: onProgress);
          _stopSetupService();
          return SetupState(
            step: SetupStep.complete,
            progress: 1.0,
            message: 'Node.js installation complete',
          );
        case SetupStep.installingStableClaw:
          await runStepInstallStableClaw(onProgress: onProgress);
          _stopSetupService();
          return SetupState(
            step: SetupStep.complete,
            progress: 1.0,
            message: 'StableClaw installation complete',
          );
        case SetupStep.configuringBypass:
          await runStepConfigureBypass(onProgress: onProgress);
          _stopSetupService();
          return SetupState(
            step: SetupStep.complete,
            progress: 1.0,
            message: 'Bionic Bypass configured',
          );
        default:
          _stopSetupService();
          return const SetupState(
            step: SetupStep.error,
            error: 'Cannot run this step individually',
          );
      }
    } on DioException catch (e) {
      _stopSetupService();
      return SetupState(
        step: SetupStep.error,
        error: 'Download failed: ${e.message}. Check your internet connection.',
      );
    } catch (e) {
      _stopSetupService();
      return SetupState(
        step: SetupStep.error,
        error: 'Step failed: $e',
      );
    }
  }

  // ──────────────────────────────────────────────
  // Full setup (sequential — runs all steps)
  // ──────────────────────────────────────────────

  Future<void> runFullSetup({
    required void Function(SetupState) onProgress,
  }) async {
    try {
      // Start foreground service to keep app alive during setup
      await _startSetupService();

      // Step 0: Setup directories
      await runStepSetupDirs(onProgress: onProgress);

      // Step 1: Download rootfs
      await runStepDownloadRootfs(onProgress: onProgress);

      // Step 2: Extract rootfs
      await runStepExtractRootfs(onProgress: onProgress);

      // Install bionic bypass before node verification (done inside runStepInstallNode)
      // Step 3: Install Node.js
      await runStepInstallNode(onProgress: onProgress);

      // Step 4: Install StableClaw
      await runStepInstallStableClaw(onProgress: onProgress);

      // Step 5: Bionic Bypass already installed (inside runStepInstallNode)
      _updateSetupNotification('Setup complete!', progress: 100);
      onProgress(const SetupState(
        step: SetupStep.configuringBypass,
        progress: 1.0,
        message: 'Bionic Bypass configured',
      ));

      // Done
      _stopSetupService();
      onProgress(const SetupState(
        step: SetupStep.complete,
        progress: 1.0,
        message: 'Setup complete! Ready to start the gateway.',
      ));
    } on DioException catch (e) {
      _stopSetupService();
      onProgress(SetupState(
        step: SetupStep.error,
        error: 'Download failed: ${e.message}. Check your internet connection.',
      ));
    } catch (e) {
      _stopSetupService();
      onProgress(SetupState(
        step: SetupStep.error,
        error: 'Setup failed: $e',
      ));
    }
  }
}
