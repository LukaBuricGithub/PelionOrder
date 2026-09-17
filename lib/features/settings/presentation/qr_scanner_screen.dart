import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // In the sensor's (landscape) frame; the new selector picks the closest
    // supported size, higher first.
    cameraResolution: const Size(1920, 1080),
    useNewCameraSelector: true,
  );
  bool _handled = false; // guard: a QR fires onDetect repeatedly per frame.

  /// 0 (no zoom) … 1 (the camera's maximum).
  double _zoom = 0;
  double _zoomAtPinchStart = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    debugPrint('QR ▸ scanned: $code');
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
    return Scaffold(
      // Black from the first frame: the camera image takes a moment to start.
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Skeniraj QR kod'),
        actions: [
          IconButton(
            tooltip: 'Bljeskalica',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
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
              // No message on screen (the package would otherwise show its
              // own): just black, with the reason in the log.
              errorBuilder: (context, error, _) {
                debugPrint(
                  'QR ▸ camera error: ${error.errorCode.name} '
                  '${error.errorDetails?.message ?? ''}',
                );
                return const ColoredBox(color: Colors.black);
              },
            ),
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
