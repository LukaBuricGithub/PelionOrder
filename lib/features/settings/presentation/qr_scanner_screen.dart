import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR scanner opened from "Postavke uređaja". On the first
/// successful scan it closes and returns the decoded string to the caller via
/// `Navigator.pop(context, code)` (the settings screen parses the licenca out
/// of it). Returns null if dismissed without a scan.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false; // guard: a QR fires onDetect repeatedly per frame.

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    debugPrint('QR ▸ scanned: $code');
    // Return the decoded string to the caller (settings screen parses it).
    if (mounted) Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
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
        ],
      ),
    );
  }
}
