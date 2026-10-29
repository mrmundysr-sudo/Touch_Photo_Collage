package com.mundymorning.collage.engine

import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutEngine
import com.mundymorning.collage.engine.layout.LayoutGenerator
import com.mundymorning.collage.engine.layout.LayoutTemplate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LayoutTest {

    private fun assertTiles(l: LayoutTemplate, n: Int) {
        assertEquals("${l.id} count", n, l.count)
        var area = 0f
        for (c in l.cells) {
            assertTrue("${l.id} in bounds $c", c.l >= -1e-5f && c.t >= -1e-5f && c.r <= 1f + 1e-5f && c.b <= 1f + 1e-5f)
            assertTrue("${l.id} positive size $c", c.w > 0.05f && c.h > 0.05f)
            area += c.area
        }
        assertEquals("${l.id} covers canvas", 1f, area, 1e-3f)
        for (i in l.cells.indices) for (j in i + 1 until l.cells.size)
            assertFalse("${l.id} overlap $i/$j", l.cells[i].overlaps(l.cells[j]))
    }

    @Test fun everyCandidateTilesTheCanvasForAnyPhotoCount() {
        for (n in 1..30) {
            val c = LayoutGenerator.candidates(n)
            assertTrue("n=$n has layouts", c.isNotEmpty())
            c.forEach { assertTiles(it, n) }
            assertEquals("unique ids n=$n", c.size, c.map { it.id }.toSet().size)
        }
    }

    @Test fun commonCountsOfferHorizontalVerticalGridAndArtisticOptions() {
        for (n in listOf(2, 3, 4, 6)) {
            val names = LayoutGenerator.candidates(n).map { it.id }
            assertTrue("n=$n has a single row", names.any { it == "rows-$n-1" })
            assertTrue("n=$n has stacked/columns", names.any { it.startsWith("cols-") || it == "rows-$n-$n" })
        }
        assertTrue(LayoutGenerator.candidates(9).any { it.id == "rows-9-3" })
        assertTrue(LayoutGenerator.candidates(4).any { it.id.startsWith("mosaic") })
        assertTrue(LayoutGenerator.candidates(5).any { it.id == "pinwheel-5" })
    }

    @Test fun mosaicIsDeterministicPerSeedAndDiffersBetweenSeeds() {
        assertEquals(LayoutGenerator.mosaic(6, 1), LayoutGenerator.mosaic(6, 1))
        assertTrue(LayoutGenerator.mosaic(6, 1).cells != LayoutGenerator.mosaic(6, 2).cells)
    }

    @Test fun gridWithColumnsRespectsColumnLimitAndFillsCanvas() {
        val g = LayoutGenerator.gridWithColumns(7, 3)
        assertTiles(g, 7)
        assertEquals(3, g.cells.count { it.t < 0.01f })
    }

    @Test fun spacingAndMarginAreExactInPixels() {
        val two = LayoutGenerator.rows(2, 1)
        val r = LayoutEngine.cellRects(two, 1000f, 500f, margin = 10f, spacing = 8f)
        assertEquals(10f, r[0].l, 1e-3f); assertEquals(10f, r[0].t, 1e-3f); assertEquals(490f, r[0].b, 1e-3f)
        assertEquals(990f, r[1].r, 1e-3f)
        assertEquals("gap between photos", 8f, r[1].l - r[0].r, 1e-3f)
    }

    @Test fun cellsNeverOverlapOrCollapseWithLargeSpacing() {
        for (n in listOf(2, 3, 4, 6, 9, 16)) for (l in LayoutGenerator.candidates(n)) {
            val rects = LayoutEngine.cellRects(l, 600f, 800f, margin = 30f, spacing = 60f)
            rects.forEach { assertTrue(it.w >= 1f && it.h >= 1f) }
            for (i in rects.indices) for (j in i + 1 until rects.size) assertFalse(rects[i].overlaps(rects[j], 0.01f))
        }
    }

    @Test fun autoPicksSideBySideForTwoPortraitsAndStackedForTwoLandscapes() {
        val portraits = List(2) { 3f / 4f }
        val (l1, c1) = LayoutGenerator.auto(portraits)
        assertTrue("two portraits side by side, wide canvas: ${l1.id} ${c1.label}", l1.id == "rows-2-1" && c1.aspect > 1f)
        val landscapes = List(2) { 4f / 3f }
        val (l2, c2) = LayoutGenerator.auto(landscapes)
        assertTrue("two landscapes stacked, tall canvas: ${l2.id} ${c2.label}", l2.id == "rows-2-2" && c2.aspect < 1f)
    }

    @Test fun cropCostIsZeroWhenAspectsMatch() {
        val l = LayoutGenerator.rows(2, 1) // two 1:2 columns of the unit square
        // on a 2:1 canvas each cell is exactly 1:1
        assertEquals(0f, LayoutGenerator.cropCost(l, 2f, listOf(1f, 1f)), 1e-4f)
        assertTrue(LayoutGenerator.cropCost(l, 1f, listOf(1f, 1f)) > 0.5f)
    }

    @Test fun canvasSizeForLongSideKeepsRatio() {
        assertEquals(2048 to 1536, LayoutEngine.sizeForLongSide(CanvasSpec.LANDSCAPE_4_3, 2048))
        assertEquals(1152 to 2048, LayoutEngine.sizeForLongSide(CanvasSpec.STORY_9_16, 2048))
        assertEquals(1000 to 1000, LayoutEngine.sizeForLongSide(CanvasSpec.SQUARE, 1000))
    }
}
