package com.mundymorning.collage.engine.face

import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.mundymorning.collage.engine.io.BitmapLoader
import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.project.PhotoRef
import java.io.File

/** Finds face boxes in a photo. Implementations must run fully on device. */
interface FaceFinder {
    /** Face boxes in upright (EXIF-applied) normalised coordinates, or null if detection is unavailable/failed. */
    fun find(ref: PhotoRef, mediaDir: File): List<FRect>?
}

/** ML Kit bundled face detector: free, on-device, no network and no identity recognition. */
class MlKitFaceFinder : FaceFinder {
    private val detector by lazy {
        FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .setMinFaceSize(0.06f)
                .build(),
        )
    }

    override fun find(ref: PhotoRef, mediaDir: File): List<FRect>? = try {
        val bmp: Bitmap = BitmapLoader.decodeUpright(File(mediaDir, ref.file), ref, 1280) ?: return null
        try {
            val faces = Tasks.await(detector.process(InputImage.fromBitmap(bmp, 0)))
            val w = bmp.width.toFloat()
            val h = bmp.height.toFloat()
            faces.map {
                val b = it.boundingBox
                // ML Kit boxes hug the face; grow slightly so the head/hair is kept in frame.
                val padX = b.width() * 0.12f
                val padTop = b.height() * 0.28f
                val padBottom = b.height() * 0.08f
                FRect(
                    ((b.left - padX) / w).coerceIn(0f, 1f), ((b.top - padTop) / h).coerceIn(0f, 1f),
                    ((b.right + padX) / w).coerceIn(0f, 1f), ((b.bottom + padBottom) / h).coerceIn(0f, 1f),
                )
            }.filter { it.w > 0.01f && it.h > 0.01f }
        } finally {
            bmp.recycle()
        }
    } catch (t: Throwable) {
        null // unreliable/unavailable: caller falls back to centre cropping
    }
}
