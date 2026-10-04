const readerKey = (key) => key === 'ereaderSettings' || key.startsWith('ebookLocations-')

/**
 * The WebView storage entries the new app's readers use. Only these leave the WebView; the native
 * export applies the same allowlist again.
 */
function collectReaderStorage(storage) {
  const collected = {}
  try {
    for (let index = 0; index < storage.length; index++) {
      const key = storage.key(index)
      if (key === null || !readerKey(key)) continue
      const value = storage.getItem(key)
      if (typeof value === 'string') collected[key] = value
    }
  } catch (error) {
    return {}
  }
  return collected
}

// The database phases are quick next to copying downloads, so they share the first tenth.
function progressFraction(progress) {
  switch (progress.phase) {
    case 'copyingDatabase':
      return 0
    case 'readingDatabase':
      return 0.05
    case 'copyingFiles': {
      if (!progress.totalBytes) return progress.completedFiles >= progress.totalFiles ? 1 : 0.1
      return 0.1 + (0.9 * progress.completedBytes) / progress.totalBytes
    }
    default:
      return 0
  }
}

function progressLabel(progress) {
  switch (progress.phase) {
    case 'copyingDatabase':
      return 'Copying the library database'
    case 'readingDatabase':
      return 'Reading the library database'
    case 'copyingFiles':
      return `Copying downloads (${progress.completedFiles} of ${progress.totalFiles})`
    default:
      return 'Preparing the export'
  }
}

export { collectReaderStorage, progressFraction, progressLabel }
