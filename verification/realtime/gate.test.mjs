import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import test from 'node:test'

test('upgrade gate identifies a missing legacy realtime progress contract', () => {
  const candidate = spawnSync(process.execPath, ['journey.mjs', 'progress-event-change'], { cwd: import.meta.dirname, encoding: 'utf8', timeout: 15000 })
  assert.equal(candidate.status, 1, candidate.stderr)
  const report = JSON.parse(candidate.stdout.trim().split('\n').at(-1))
  assert.equal(report.result, 'failed')
  assert.equal(report.workflow, 'realtime-progress')
})
