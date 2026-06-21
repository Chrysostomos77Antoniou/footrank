package com.footballcy.footrank

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "footrank/gallery"
    private val pickRequestCode = 90111
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImageFromGallery" -> {
                        if (pendingResult != null) {
                            result.error("busy", "A pick is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        // ACTION_PICK opens the device gallery directly (not the file browser).
                        val intent = Intent(
                            Intent.ACTION_PICK,
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        )
                        intent.type = "image/*"
                        try {
                            startActivityForResult(intent, pickRequestCode)
                        } catch (e: Exception) {
                            pendingResult = null
                            result.error("no_gallery", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequestCode) return
        val result = pendingResult ?: return
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null) // user cancelled
            return
        }
        try {
            val uri: Uri = data.data!!
            val input = contentResolver.openInputStream(uri)
            val original = BitmapFactory.decodeStream(input)
            input?.close()
            if (original == null) {
                result.error("decode_failed", "Could not read the image", null)
                return
            }
            // Downscale so uploads stay small (max 1024px on the longest side).
            val maxDim = 1024
            val longest = maxOf(original.width, original.height)
            val scale = if (longest > maxDim) maxDim.toFloat() / longest else 1f
            val scaled = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    original,
                    (original.width * scale).toInt(),
                    (original.height * scale).toInt(),
                    true
                )
            } else {
                original
            }
            val file = File(cacheDir, "footrank_pick_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
            result.success(file.absolutePath)
        } catch (e: Exception) {
            result.error("read_failed", e.message, null)
        }
    }
}
