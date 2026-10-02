package com.audiobookshelf.android.journeys

import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.AppGraph
import com.audiobookshelf.android.migration.Migration
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** A chosen export is still being read when the user closes the import or chooses another file. */
@RunWith(AndroidJUnit4::class)
class MigrationSelectionJourney {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val root = File(instrumentation.targetContext.cacheDir, "migration-selection")
    private val cache = File(root, "cache")

    private val graph = AppGraph(object : ContextWrapper(instrumentation.targetContext.applicationContext) {
        override fun getFilesDir() = File(root, "files").apply { mkdirs() }
        override fun getNoBackupFilesDir() = File(root, "no-backup").apply { mkdirs() }
        override fun getCacheDir() = cache.apply { mkdirs() }
        override fun getApplicationContext(): Context = this
    })

    private fun uri(name: String) = Uri.parse("content://com.audiobookshelf.journeys.archives/$name")
    private fun onMain(block: () -> Unit) = instrumentation.runOnMainSync(block)
    private val migration get() = graph.migration
    private fun leftovers() = cache.walkTopDown().filter { it.isFile }.toList()

    @Before fun clean() { root.deleteRecursively() }
    @After fun remove() { root.deleteRecursively() }

    @Test
    fun closingWhileAnExportIsReadLeavesTheImportClosedAndNothingBehind() {
        onMain { migration.open(uri("slow-legacy-export.absmigration")) }
        Thread.sleep(500)
        onMain { migration.close() }
        // The slow export arrives after two seconds; its read must not reopen the import.
        Thread.sleep(4_000)
        assertNull(migration.step.value)
        assertEquals(emptyList<File>(), leftovers())
    }

    @Test
    fun aNewSelectionReplacesOneStillBeingRead() {
        onMain { migration.open(uri("slow-legacy-export.absmigration")) }
        Thread.sleep(500)
        onMain { migration.open(uri("legacy-export.absmigration")) }
        eventually { migration.step.value is Migration.Step.Ready }
        Thread.sleep(4_000)
        val shown = migration.step.value
        assertTrue("The later choice stays shown: $shown", shown is Migration.Step.Ready && shown.name == "legacy-export.absmigration")
        onMain { migration.close() }
        eventually { leftovers().isEmpty() }
    }
}
