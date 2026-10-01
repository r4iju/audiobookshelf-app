<template>
  <div>
    <p class="uppercase text-xs font-semibold text-fg-muted mb-2 mt-10">Move to the new app</p>
    <p class="text-sm text-fg-muted py-1">Exports your servers, settings, listening progress, downloads and reader positions as one file for the new Audiobookshelf app. Passwords and sign-in tokens are not included, so you sign in again in the new app. This app and its downloads stay as they are.</p>

    <div v-if="state === 'exporting'" class="py-3">
      <p class="text-sm">{{ label }}</p>
      <div class="w-full h-1.5 bg-bg-hover rounded mt-2 overflow-hidden">
        <div class="h-full bg-success rounded" :style="{ width: `${Math.round(fraction * 100)}%` }" />
      </div>
    </div>

    <div v-else-if="state === 'ready' || state === 'saved'" class="py-3">
      <p class="text-sm break-all">{{ result.name }}</p>
      <p class="text-xs text-fg-muted">{{ result.files }} files, {{ $bytesPretty(result.bytes) }}</p>
      <p v-if="state === 'saved'" class="text-sm text-success py-1">Saved. Open the new app and import this file. You can remove it from here when the import has finished.</p>
      <p v-else class="text-sm text-fg-muted py-1">Choose "On My iPhone" in the save dialog to keep the file off cloud storage.</p>
      <div class="flex items-center pt-2">
        <ui-btn small :loading="saving" @click="save">Save to Files</ui-btn>
        <ui-btn small class="ml-2" :disabled="saving" @click="discard">Remove export</ui-btn>
      </div>
    </div>

    <div v-else class="py-3">
      <p v-if="error" class="text-sm text-error py-1">{{ error }}</p>
      <ui-btn small @click="start">{{ error ? 'Try again' : 'Export for the new app' }}</ui-btn>
    </div>
  </div>
</template>

<script>
import { LegacyMigrationExport, collectReaderStorage, progressFraction, progressLabel } from '@/plugins/legacyMigrationExport'

export default {
  data() {
    return {
      state: 'idle',
      progress: { phase: 'copyingDatabase' },
      result: null,
      error: null,
      saving: false,
      listener: null
    }
  },
  computed: {
    fraction() {
      return progressFraction(this.progress)
    },
    label() {
      return progressLabel(this.progress)
    }
  },
  methods: {
    async start() {
      this.state = 'exporting'
      this.error = null
      this.result = null
      this.progress = { phase: 'copyingDatabase' }
      try {
        this.result = await LegacyMigrationExport.exportArchive({ webStorage: collectReaderStorage(window.localStorage) })
        this.state = 'ready'
      } catch (error) {
        this.error = error?.message || 'The export failed. Nothing was changed.'
        this.state = 'idle'
      }
    },
    async save() {
      this.saving = true
      try {
        const { saved } = await LegacyMigrationExport.saveArchive()
        if (saved) this.state = 'saved'
      } catch (error) {
        this.error = error?.message || 'The file could not be saved.'
        this.state = 'idle'
      } finally {
        this.saving = false
      }
    },
    async discard() {
      try {
        await LegacyMigrationExport.discardArchive()
      } catch (error) {
        this.error = error?.message || 'The export could not be removed.'
      }
      this.result = null
      this.state = 'idle'
    }
  },
  mounted() {
    this.listener = LegacyMigrationExport.addListener('exportProgress', (progress) => {
      this.progress = progress
    })
  },
  beforeDestroy() {
    this.listener?.then((handle) => handle.remove())
  }
}
</script>
