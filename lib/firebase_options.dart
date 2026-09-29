import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase credentials for the **pelion-order** project, used to initialise
/// Firebase programmatically where the platform's own config file isn't
/// reliably present in the compiled app.
///
/// **iOS** — the builds are made on Codemagic, which never opens Xcode's UI,
/// so `ios/Runner/GoogleService-Info.plist` is never registered in the Runner
/// target's "Copy Bundle Resources" phase. The file therefore sits in the
/// source tree but does NOT ship inside the `.ipa`, and the iOS SDK's default
/// lookup (`pathForResource:@"GoogleService-Info"`) returns nil. Passing
/// [FirebaseOptions] explicitly skips the bundle lookup entirely.
///
/// **Android** — `android/app/google-services.json` IS baked into the app's
/// resources by the Google Services Gradle plugin, so `initializeApp()` with
/// no arguments works and the Android credentials are deliberately not
/// duplicated here (one source of truth per platform).
///
/// The values below are copied verbatim from the plist. If a credential is
/// ever rotated in the Firebase Console, update BOTH the plist and this file.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// iOS configuration for Pelion Order.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAvmRz0cwpIFFWg1dO5gf_HsDVM7aIVR5Y',
    appId: '1:808786642476:ios:101ffcc95be89a319ef389',
    messagingSenderId: '808786642476',
    projectId: 'pelion-order',
    storageBucket: 'pelion-order.firebasestorage.app',
    iosBundleId: 'hr.pelion.order',
  );
}
