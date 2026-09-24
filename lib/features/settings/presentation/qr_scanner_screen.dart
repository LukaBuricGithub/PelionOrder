import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shared/platform/open_app_settings.dart';

/// Full-screen QR scanner opened from "Postavke uređaja". On the first
/// successful scan it closes and returns the decoded string to the caller via
/// `Navigator.pop(context, code)` (the settings screen parses the licenca out
/// of it). Returns null if dismissed without a scan.
///
/// The orderman code is a dense QR (a whole JSON object), so the camera is
/// asked for a higher analysis resolution than the default 640×480 — on some
/// phones (seen on a Samsung A) the default is too coarse to read it. Zoom
/// (slider and pinch) lets the waiter hold the phone further away, where a
/// camera that can't focus up close still gets a sharp image.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  /// Slides in from the right, fully opaque. The default Android transition
  /// cross-fades the pages, and against "Postavke uređaja" (which stays still
  /// underneath) the two app bar titles showed through each other.
  static Route<String> route() => PageRouteBuilder<String>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) => const QrScannerScreen(),
    transitionsBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    ),
  );

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // In the sensor's (landscape) frame; Android's resolution selector picks
    // the closest supported size, higher first. (Android only — iOS decides
    // its own capture size.)
    cameraResolution: const Size(1920, 1080),
  );
  bool _handled = false; // guard: a QR fires onDetect repeatedly per frame.

  /// 0 (no zoom) … 1 (the camera's maximum).
  double _zoom = 0;
  double _zoomAtPinchStart = 0;

  /// The waiter went to the phone's settings to allow the camera: try the
  /// camera again when they come back.
  bool _toSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _toSettings) {
      _toSettings = false;
      _retryCamera();
    }
  }

  /// Camera access was refused. iOS asks only once, and Android stops asking
  /// after "Ne pitaj ponovno", so the only way back is the app's page in the
  /// phone's settings.
  Future<void> _openSettings() async {
    _toSettings = true;
    // Didn't open (no settings app answered): nothing changes, the message
    // stays and the camera isn't retried.
    if (!await openAppSettings()) _toSettings = false;
  }

  /// Starts the camera again. A refusal sticks to the controller until it is
  /// stopped, so stop first; if access is still refused, the message stays.
  /// (On iOS, allowing the camera in the settings restarts the app anyway.)
  Future<void> _retryCamera() async {
    try {
      await _controller.stop();
      await _controller.start();
    } catch (e) {
      debugPrint('QR ▸ camera restart failed: $e');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    // The code holds the venue's licence: printed in debug builds only.
    debugPrint(kDebugMode ? 'QR ▸ scanned: $code' : 'QR ▸ scanned');
    // Return the decoded string to the caller (settings screen parses it).
    if (mounted) Navigator.of(context).pop(code);
  }

  void _setZoom(double value) {
    final zoom = value.clamp(0.0, 1.0);
    if (zoom == _zoom) return;
    setState(() => _zoom = zoom);
    _controller.setZoomScale(zoom).catchError((Object e) {
      debugPrint('QR ▸ zoom failed: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, scanner, _) {
        // No camera access: the message below replaces the aiming square
        // and the zoom bar — neither of them can do anything.
        final denied =
            scanner.error?.errorCode == MobileScannerErrorCode.permissionDenied;
        return _buildScaffold(denied);
      },
    );
  }

  Widget _buildScaffold(bool denied) {
    return Scaffold(
      // Black from the first frame: the camera image takes a moment to start.
      backgroundColor: Colors.black,
      // No flashlight button: the code is read off the kasa's lit screen,
      // where a flash only adds glare, and not every phone has one.
      appBar: AppBar(title: const Text('Skeniraj QR kod')),
      // StackFit.expand forces the stack to fill the screen from the first
      // frame, so the aiming square is centred immediately instead of jumping
      // in from the top-left once the camera preview reports its size.
      body: GestureDetector(
        onScaleStart: (_) => _zoomAtPinchStart = _zoom,
        onScaleUpdate: (d) {
          if (d.pointerCount < 2) return;
          _setZoom(_zoomAtPinchStart + (d.scale - 1) * 0.5);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              // Camera access refused: one message, with the way to allow it.
              // Any other camera error shows no message (the package would
              // otherwise show its own): just black, with the reason in the
              // log.
              errorBuilder: (context, error) {
                debugPrint(
                  'QR ▸ camera error: ${error.errorCode.name} '
                  '${error.errorDetails?.message ?? ''}',
                );
                if (error.errorCode ==
                    MobileScannerErrorCode.permissionDenied) {
                  return _CameraDenied(onOpenSettings: _openSettings);
                }
                return const ColoredBox(color: Colors.black);
              },
            ),
            if (!denied) ...[
              // Aiming guide, centred in the full screen.
              Center(
                child: IgnorePointer(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: SafeArea(
                  top: false,
                  child: _ZoomBar(value: _zoom, onChanged: _setZoom),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown instead of the camera image when camera access has been refused —
/// the one camera error with a message, because without the camera the phone
/// can't be set up, and the fix is somewhere the waiter wouldn't look.
class _CameraDenied extends StatelessWidget {
  const _CameraDenied({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  size: 56,
                  color: Colors.white70,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Nema pristupa kameri',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Za skeniranje QR koda dopustite pristup kameri u '
                  'postavkama telefona.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Otvori postavke'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zoom slider over the camera image.
class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Smanji',
              color: Colors.white,
              icon: const Icon(Icons.zoom_out),
              onPressed: () => onChanged(value - 0.1),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(value: value, onChanged: onChanged),
              ),
            ),
            IconButton(
              tooltip: 'Povećaj',
              color: Colors.white,
              icon: const Icon(Icons.zoom_in),
              onPressed: () => onChanged(value + 0.1),
            ),
          ],
        ),
      ),
    );
  }
}
