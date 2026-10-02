package com.audiobookshelf.core

import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull

class CarBrowsingTest {
    private val names = listOf("ada", "Alan", "Bea", "bruno", "Cara", "Al")

    @Test
    fun namesWithinTheLimitAreNotGrouped() {
        assertNull(CarBrowsing.groups(names, limit = 6))
    }

    @Test
    fun moreNamesThanTheLimitAreGroupedByTheirFirstLetterIgnoringCase() {
        assertEquals(listOf(CarBrowsing.Group("A", 3), CarBrowsing.Group("B", 2), CarBrowsing.Group("C", 1)), CarBrowsing.groups(names, limit = 2))
    }

    @Test
    fun aGroupStillOverTheLimitSplitsByOneMoreLetterAndKeepsNamesAsLongAsItsPrefix() {
        val group = names.filter { CarBrowsing.inGroup(it, "A") }
        assertEquals(listOf(CarBrowsing.Group("AD", 1), CarBrowsing.Group("AL", 2)), CarBrowsing.groups(group, limit = 2, prefix = "A"))
        // "Al" is no longer than the prefix "AL"; it stays listed there rather than failing.
        assertNull(CarBrowsing.groups(listOf("Al", "Alan"), limit = 1, prefix = "AL"))
    }

    @Test
    fun namesThatShareOneLetterSplitFurtherInsteadOfShowingASingleGroup() {
        assertEquals(listOf(CarBrowsing.Group("ABA", 2), CarBrowsing.Group("ABB", 1)), CarBrowsing.groups(listOf("Abaa", "Abab", "Abba"), limit = 2))
    }

    @Test
    fun seriesSequencesSortNumericallyWithUnnumberedBooksLast() {
        val sequences = listOf("10", null, "2", "1.5", "1", "1.10", "Part B", "0.5")
        assertEquals(listOf("0.5", "1", "1.5", "1.10", "2", "10", "Part B", null), sequences.sortedWith(CarBrowsing.bySequence))
    }

    @Test
    fun seriesAndCollapsedSeriesFromFilteredListsAreRead() {
        val inSeries = AbsJson.decodeFromString(LibraryItem.serializer(), """{"id":"b","media":{"metadata":{"title":"B","series":{"id":"s","name":"Saga","sequence":"2"}}}}""")
        assertEquals(listOf(SeriesRef("s", "Saga", "2")), inSeries.media.metadata.series)
        val collapsed = AbsJson.decodeFromString(LibraryItem.serializer(), """{"id":"b","media":{"metadata":{"title":"B"}},"collapsedSeries":{"id":"s","name":"Saga","numBooks":3}}""")
        assertEquals("Saga", collapsed.collapsedSeries?.name)
        assertEquals(3, collapsed.collapsedSeries?.numBooks)
    }
}
