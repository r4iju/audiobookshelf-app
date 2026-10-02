import assert from 'node:assert/strict'
import test from 'node:test'
import { runJourney } from './journey.mjs'

test('legacy production socket authenticates under a subpath, applies progress and re-authenticates after reconnect', async () => {
  const report = await runJourney()
  assert.equal(report.result, 'passed')
  assert.deepEqual(report.workflows, ['realtime-authentication', 'realtime-progress', 'realtime-reconnection'])
  assert.equal(report.observations.authenticatedConnections, 2)
  assert.equal(report.observations.progressApplied, true)
  assert.equal(report.observations.disconnected, true)
})
