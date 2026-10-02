// Run inside the pinned 2.30.0 image with models/User.js mounted read-only (see invalidation-during-load-check.txt).
// A request misses the cache and starts loading the user. While that load is awaiting, the user is changed and the
// cache invalidated (a save through an object that is not the cached one). The request must not go on with the
// object read before the change, and the cache must not keep it.
const assert = require('assert')
const User = require('/app/server/models/User.js')
// The lookups only read sequelize.models to build the query, which the stub ignores.
Object.defineProperty(User, 'sequelize', { value: { models: {} } })
const database = { u1: 1, u2: 1 } // version of each user's stored row
let loads = 0
User.findByPk = async (id) => {
  loads++
  const version = database[id] // read when the query starts
  await new Promise((resolve) => setTimeout(resolve, 30))
  return { id, username: id, extraData: {}, mediaProgresses: [], version }
}
const invalidate = (id) => {
  const other = Object.create(User.prototype)
  other.id = id
  other.fromCache = false
  other.save().catch(() => {}) // maybeInvalidate runs before the (stubbed-out) database save fails
}
const check = async (name, body) => {
  try {
    await body()
    console.log(`PASS ${name}`)
  } catch (error) {
    console.log(`FAIL ${name}: ${error.message}`)
    process.exitCode = 1
  }
}
;(async () => {
  await check('a change during the load is not returned stale or cached', async () => {
    loads = 0
    const pending = User.getUserById('u1')
    await new Promise((resolve) => setTimeout(resolve, 10))
    database.u1 = 2
    invalidate('u1')
    const user = await pending
    const cached = await User.getUserById('u1')
    console.log(`  request got version ${user.version}, cache then gave version ${cached.version}, ${loads} loads`)
    assert.strictEqual(user.version, 2, 'the request went on with the user read before the change')
    assert.strictEqual(cached.version, 2, 'the cache kept the user read before the change')
  })
  await check('another user changing during the load costs no reload', async () => {
    loads = 0
    const pending = User.getUserById('u2')
    await new Promise((resolve) => setTimeout(resolve, 10))
    invalidate('someone-else')
    const user = await pending
    console.log(`  request got version ${user.version}, ${loads} loads`)
    assert.strictEqual(loads, 1, 'an unrelated invalidation forced a reload')
  })
  await check('a user changed during every load still gets an answer after at most three loads', async () => {
    loads = 0
    const churn = setInterval(() => {
      database.u3 = (database.u3 ?? 0) + 1
      invalidate('u3')
    }, 5)
    const user = await User.getUserById('u3')
    clearInterval(churn)
    console.log(`  request got version ${user.version}, ${loads} loads`)
    assert.ok(loads <= 3, `${loads} loads`)
  })
})()
