// Run from the repository root: node --test apple/Migration/LegacyExportWebTests/
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { collectReaderStorage, progressFraction, progressLabel } from './legacyMigrationExport.js'

function storage(entries) {
  const keys = Object.keys(entries)
  return { length: keys.length, key: (index) => keys[index] ?? null, getItem: (key) => (key in entries ? entries[key] : null) }
}

test('only reader settings and saved reader locations leave the WebView', () => {
  const collected = collectReaderStorage(
    storage({
      ereaderSettings: '{"fontScale":1.2}',
      'ebookLocations-li-1': '{"locations":"[]"}',
      'ebookLocations-li-2': '{"locations":"[1]"}',
      absDeviceId: 'device-1',
      device: '{"serverConnectionConfigs":[{"token":"SYNTHETIC"}]}',
      'refresh_token_conn-1': 'SYNTHETIC-REFRESH',
      serverSettings: '{}'
    })
  )
  assert.deepEqual(collected, {
    ereaderSettings: '{"fontScale":1.2}',
    'ebookLocations-li-1': '{"locations":"[]"}',
    'ebookLocations-li-2': '{"locations":"[1]"}'
  })
})

test('an unreadable storage yields nothing rather than failing the export', () => {
  assert.deepEqual(collectReaderStorage(null), {})
  assert.deepEqual(collectReaderStorage({ get length() { throw new Error('denied') } }), {})
})

test('progress moves forward through the phases and ends complete', () => {
  const events = [
    { phase: 'copyingDatabase' },
    { phase: 'readingDatabase' },
    { phase: 'copyingFiles', completedFiles: 0, totalFiles: 2, completedBytes: 0, totalBytes: 100 },
    { phase: 'copyingFiles', completedFiles: 1, totalFiles: 2, completedBytes: 40, totalBytes: 100 },
    { phase: 'copyingFiles', completedFiles: 2, totalFiles: 2, completedBytes: 100, totalBytes: 100 }
  ]
  const fractions = events.map(progressFraction)
  for (let i = 1; i < fractions.length; i++) assert.ok(fractions[i] > fractions[i - 1], `fraction ${i} increases`)
  assert.equal(fractions[0], 0)
  assert.equal(fractions.at(-1), 1)
  assert.equal(progressFraction({ phase: 'copyingFiles', completedFiles: 0, totalFiles: 0, completedBytes: 0, totalBytes: 0 }), 1)
  assert.equal(progressLabel(events[3]), 'Copying downloads (1 of 2)')
  assert.equal(progressLabel(events[0]), 'Copying the library database')
  assert.equal(progressLabel(events[1]), 'Reading the library database')
})
