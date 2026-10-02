// Run inside the pinned 2.30.0 image with models/User.js mounted read-only (see concurrent-load-check.txt).
// Two requests for one user miss the empty cache at once; the first load finishes first. Both must get the object the
// cache keeps, or a progress update made through one is never seen by reads through the cache.
const assert = require('assert')
const User = require('/app/server/models/User.js')
// The lookups only read sequelize.models to build the query, which the stub ignores.
Object.defineProperty(User, 'sequelize', { value: { models: {} } })
let loads = 0
User.findByPk = async (id) => {
  const n = ++loads
  await new Promise((resolve) => setTimeout(resolve, n === 1 ? 10 : 30))
  return { id, username: 'qa', extraData: {}, mediaProgresses: [], load: n }
}
;(async () => {
  const [first, second] = await Promise.all([User.getUserById('u1'), User.getUserById('u1')])
  const cached = await User.getUserById('u1')
  console.log(`first request got load ${first.load}, second got load ${second.load}, cache holds load ${cached.load}`)
  assert.strictEqual(first, cached, 'the first request holds an object the cache no longer returns')
  assert.strictEqual(second, cached, 'the second request holds an object the cache no longer returns')
  console.log('PASS')
})().catch((error) => {
  console.log(`FAIL: ${error.message}`)
  process.exit(1)
})
