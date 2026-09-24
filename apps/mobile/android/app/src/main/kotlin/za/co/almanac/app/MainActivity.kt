package za.co.almanac.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The self-test's AR and depth check. See DeviceProbe.kt.
        DeviceProbe(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
