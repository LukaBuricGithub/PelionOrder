package hr.pelion.order

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The waiter is answering the Bluetooth permission dialog right now; the
    // Dart side waits on this until onRequestPermissionsResult comes back.
    private var pendingBluetooth: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hr.pelion.order/app_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> openAppSettings(result)
                "requestBluetooth" -> requestBluetooth(result)
                else -> result.notImplemented()
            }
        }
    }

    // Opens this app's own page in the phone's settings, so camera or
    // Bluetooth access can be granted after it was refused (Android stops
    // asking once the waiter has ticked "Ne pitaj ponovno"). Called from
    // lib/features/shared/platform/open_app_settings.dart; iOS does the same
    // with the "app-settings:" URL.
    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.fromParts("package", packageName, null)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    // Asks for the Bluetooth permissions and answers only once the waiter has
    // decided — the printer plugin only reports the current state, so asking
    // through it always failed the first time, while the dialog was open.
    //
    // BOTH permissions are needed, even though nothing here scans: the printer
    // plugin calls cancelDiscovery() before connecting, and on Android 12+
    // that call is refused without BLUETOOTH_SCAN ("Need
    // android.permission.BLUETOOTH_SCAN permission ... cancelDiscovery").
    //
    // Returns "granted", "denied" (ask again next time) or "permanentlyDenied"
    // (Android won't ask again; only the app's settings page can grant it).
    private fun requestBluetooth(result: MethodChannel.Result) {
        // Before Android 12 the Bluetooth permissions are granted at install.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success("granted")
            return
        }
        val missing = BLUETOOTH_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) !=
                PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success("granted")
            return
        }
        // A dialog is already up: let that one answer.
        if (pendingBluetooth != null) {
            result.success("denied")
            return
        }
        pendingBluetooth = result
        ActivityCompat.requestPermissions(
            this,
            missing.toTypedArray(),
            REQUEST_BLUETOOTH,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLUETOOTH) return
        val result = pendingBluetooth ?: return
        pendingBluetooth = null

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (granted) {
            result.success("granted")
            return
        }
        // Android shows a rationale only while it is still willing to ask.
        val canAskAgain = BLUETOOTH_PERMISSIONS.any {
            ActivityCompat.shouldShowRequestPermissionRationale(this, it)
        }
        result.success(if (canAskAgain) "denied" else "permanentlyDenied")
    }

    companion object {
        private const val REQUEST_BLUETOOTH = 4201

        private val BLUETOOTH_PERMISSIONS = listOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
        )
    }
}
