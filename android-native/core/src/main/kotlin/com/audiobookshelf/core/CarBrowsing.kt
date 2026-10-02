package com.audiobookshelf.core

/** Long author and series lists as the existing app shows them in the car: in letter groups a driver can scan. */
object CarBrowsing {
    data class Group(val prefix: String, val count: Int)

    /**
     * Splits [names] (all within [prefix]) into groups by one more letter once there are more than
     * [limit]; null when they should be listed as they are. A split that would only repeat the
     * current group is not offered, so every group opens onto something new.
     */
    fun groups(names: List<String>, limit: Int, prefix: String = ""): List<Group>? {
        if (names.size <= limit || names.size <= 1) return null
        var current = prefix.uppercase()
        while (true) {
            val keyed = names.groupingBy { it.uppercase().take(current.length + 1) }.eachCount()
            if (current in keyed) return null
            if (keyed.size > 1) return keyed.toSortedMap().map { (key, count) -> Group(key, count) }
            current = keyed.keys.single()
        }
    }

    fun inGroup(name: String, prefix: String): Boolean = name.uppercase().startsWith(prefix.uppercase())

    private val numbered = Regex("""^(\d+)(?:\.(\d+))?$""")

    private fun compareNumbers(a: String, b: String): Int {
        val left = a.trimStart('0'); val right = b.trimStart('0')
        return compareValuesBy(left, right, { it.length }, { it })
    }

    /** A book without a part number (`1`) comes before its parts (`1.1`). */
    private fun compareMinor(a: String, b: String): Int = when {
        a.isEmpty() || b.isEmpty() -> compareValues(a.isNotEmpty(), b.isNotEmpty())
        else -> compareNumbers(a, b)
    }

    /** Series order: numbered books by number (`1.10` after `1.5`), then other labels, then unnumbered books. */
    val bySequence: Comparator<String?> = Comparator { a, b ->
        val left = a?.trim()?.let(numbered::matchEntire)
        val right = b?.trim()?.let(numbered::matchEntire)
        when {
            a == null || b == null -> compareValues(a == null, b == null)
            left != null && right != null -> compareNumbers(left.groupValues[1], right.groupValues[1]).takeIf { it != 0 }
                ?: compareMinor(left.groupValues[2], right.groupValues[2])
            left != null -> -1
            right != null -> 1
            else -> a.compareTo(b, ignoreCase = true)
        }
    }
}
