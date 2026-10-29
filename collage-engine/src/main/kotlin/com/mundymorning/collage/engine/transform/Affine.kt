package com.mundymorning.collage.engine.transform

/** 2D affine map: x' = a*x + c*y + tx ; y' = b*x + d*y + ty. */
data class Affine(
    val a: Float = 1f, val b: Float = 0f,
    val c: Float = 0f, val d: Float = 1f,
    val tx: Float = 0f, val ty: Float = 0f,
) {
    fun mapX(x: Float, y: Float): Float = a * x + c * y + tx
    fun mapY(x: Float, y: Float): Float = b * x + d * y + ty

    /** Returns the map "first this, then [next]". */
    fun then(next: Affine): Affine = Affine(
        a = next.a * a + next.c * b,
        b = next.b * a + next.d * b,
        c = next.a * c + next.c * d,
        d = next.b * c + next.d * d,
        tx = next.a * tx + next.c * ty + next.tx,
        ty = next.b * tx + next.d * ty + next.ty,
    )

    /** Values in android.graphics.Matrix order (MSCALE_X, MSKEW_X, MTRANS_X, MSKEW_Y, MSCALE_Y, MTRANS_Y, 0, 0, 1). */
    fun toMatrixValues(): FloatArray = floatArrayOf(a, c, tx, b, d, ty, 0f, 0f, 1f)

    companion object {
        val IDENTITY = Affine()
        fun scale(sx: Float, sy: Float) = Affine(a = sx, d = sy)
        fun translate(dx: Float, dy: Float) = Affine(tx = dx, ty = dy)
    }
}
