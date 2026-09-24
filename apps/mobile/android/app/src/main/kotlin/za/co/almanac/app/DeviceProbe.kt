package za.co.almanac.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableSdkTooOldException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The self-test's AR surface and depth check (issue #4), on ARCore.
 *
 * Runs one short ARCore session with no view — an offscreen GL context gives
 * ARCore the camera texture it insists on — and reports what it saw: whether
 * ARCore is available, how many planes it found, and whether the Depth API
 * delivered a depth image. `lib/data/device/ar_probe.dart` turns those facts
 * into pass / fail / not supported.
 *
 * Every path returns a map; nothing here may throw into Flutter. A phone
 * without ARCore, or an emulator, answers `arAvailable: false`.
 */
class DeviceProbe(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "arProbe" -> {
                val timeoutMs = (call.argument<Int>("timeoutMs") ?: 20000).toLong()
                if (!busy.compareAndSet(false, true)) {
                    result.success(mapOf("arAvailable" to true, "error" to "A check is already running."))
                    return
                }
                cancelled.set(false)
                // ARCore's update loop blocks; keep it off the platform thread.
                Thread({
                    val facts = try {
                        probe(timeoutMs)
                    } catch (t: Throwable) {
                        mapOf<String, Any>(
                            "arAvailable" to true,
                            "error" to (t.message ?: t.javaClass.simpleName),
                        )
                    } finally {
                        busy.set(false)
                    }
                    main.post { result.success(facts) }
                }, "almanac-ar-probe").start()
            }
            // The self-test was left, or timed out: end the session now so it
            // stops holding the camera. The loop checks this every frame.
            "arCancel" -> {
                cancelled.set(true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun probe(timeoutMs: Long): Map<String, Any> {
        val arCore = ArCoreApk.getInstance()
        var availability = arCore.checkAvailability(context)
        // The first call can answer "still checking" while it asks Play.
        val checkUntil = SystemClock.elapsedRealtime() + 3000
        while (availability.isTransient && SystemClock.elapsedRealtime() < checkUntil) {
            Thread.sleep(200)
            availability = arCore.checkAvailability(context)
        }
        if (!availability.isSupported) {
            return mapOf("arAvailable" to false, "reason" to availability.name)
        }
        if (availability != ArCoreApk.Availability.SUPPORTED_INSTALLED) {
            return mapOf(
                "arAvailable" to true,
                "arInstalled" to false,
                "reason" to availability.name,
            )
        }
        if (context.checkSelfPermission(Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return mapOf("arAvailable" to true, "cameraPermission" to false)
        }

        val session = try {
            Session(context)
        } catch (e: UnavailableArcoreNotInstalledException) {
            return mapOf("arAvailable" to true, "arInstalled" to false, "reason" to "not installed")
        } catch (e: UnavailableApkTooOldException) {
            return mapOf("arAvailable" to true, "arInstalled" to false, "reason" to "too old")
        } catch (e: UnavailableSdkTooOldException) {
            return mapOf("arAvailable" to true, "error" to "This build's ARCore SDK is too old.")
        } catch (e: UnavailableDeviceNotCompatibleException) {
            return mapOf("arAvailable" to false, "reason" to "device not compatible")
        }

        val gl = OffscreenGl()
        try {
            val depthAvailable = session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            val config = Config(session).apply {
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                if (depthAvailable) depthMode = Config.DepthMode.AUTOMATIC
            }
            session.configure(config)
            session.setCameraTextureName(gl.texture)
            session.resume()

            var planes = 0
            var depthFrames = 0
            var trackingFrames = 0
            val until = SystemClock.elapsedRealtime() + timeoutMs
            while (SystemClock.elapsedRealtime() < until && !cancelled.get()) {
                val frame = session.update()
                if (frame.camera.trackingState == TrackingState.TRACKING) trackingFrames++
                planes = session.getAllTrackables(Plane::class.java).count {
                    it.trackingState == TrackingState.TRACKING && it.subsumedBy == null
                }
                if (depthAvailable && depthFrames == 0) {
                    try {
                        val image = frame.acquireDepthImage16Bits()
                        depthFrames++
                        image.close()
                    } catch (e: NotYetAvailableException) {
                        // Depth needs a little motion first. Keep going.
                    }
                }
                if (planes > 0 && (!depthAvailable || depthFrames > 0)) break
                Thread.sleep(33)
            }
            session.pause()
            return mapOf(
                "arAvailable" to true,
                "depthAvailable" to depthAvailable,
                "planesDetected" to planes,
                "depthFrames" to depthFrames,
                "trackingFrames" to trackingFrames,
            )
        } finally {
            session.close()
            gl.release()
        }
    }

    /**
     * A 1x1 pbuffer and an external texture: the least GL ARCore will accept.
     * Made current on the probe thread, and released on the same thread.
     */
    private class OffscreenGl {
        private val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        private val eglContext: EGLContext
        private val surface: EGLSurface
        val texture: Int

        init {
            val version = IntArray(2)
            check(EGL14.eglInitialize(display, version, 0, version, 1)) { "EGL did not initialise" }
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            EGL14.eglChooseConfig(
                display,
                intArrayOf(
                    EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                    EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                    EGL14.EGL_RED_SIZE, 8,
                    EGL14.EGL_GREEN_SIZE, 8,
                    EGL14.EGL_BLUE_SIZE, 8,
                    EGL14.EGL_NONE,
                ),
                0, configs, 0, 1, count, 0,
            )
            check(count[0] > 0) { "No EGL config for an offscreen surface" }
            eglContext = EGL14.eglCreateContext(
                display, configs[0], EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
            )
            surface = EGL14.eglCreatePbufferSurface(
                display, configs[0],
                intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0,
            )
            check(EGL14.eglMakeCurrent(display, surface, surface, eglContext)) { "EGL context would not bind" }
            val names = IntArray(1)
            GLES20.glGenTextures(1, names, 0)
            texture = names[0]
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        }

        fun release() {
            GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, surface)
            EGL14.eglDestroyContext(display, eglContext)
            // Not eglTerminate: the default display is shared with Flutter's
            // own renderer in this process.
            EGL14.eglReleaseThread()
        }
    }

    companion object {
        const val CHANNEL = "za.co.almanac.app/device_probe"
    }
}
