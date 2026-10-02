// Run inside the pinned 2.30.0 image with models/User.js mounted read-only (see seam-checks.txt).
// User.save/update/destroy invalidate the cache and then await the database write. A lookup that loads while that write
// is still in flight reads the row before it. It must not go on with that row or cache it once the write lands.
const assert = require('assert')
const User = require('/app/server/models/User.js')
// The lookups only read sequelize.models to build the query, which the stub ignores.
Object.defineProperty(User, 'sequelize', { value: { models: {} } })
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const database = { u1: 1 } // version of the stored row
let loads = 0
User.findByPk = async (id) => {
  loads++
  const version = database[id] // read when the query starts
  await delay(30)
  return { id, username: id, extraData: {}, mediaProgresses: [], version }
}
// The model's own database write, as User.save calls it through super.save: it lands 20 ms after the call.
Object.getPrototypeOf(User.prototype).save = async function () {
  await delay(20)
  database[this.id] = 2
  return this
}
;(async () => {
  try {
    const writer = Object.create(User.prototype)
    writer.id = 'u1'
    writer.fromCache = false
    const saving = writer.save() // invalidates, then writes
    await delay(5)
    const user = await User.getUserById('u1') // loads while the write is in flight
    await saving
    const cached = await User.getUserById('u1')
    console.log(`  request got version ${user.version}, cache then gave version ${cached.version}, ${loads} loads`)
    assert.strictEqual(user.version, 2, 'the request went on with the row read before the write landed')
    assert.strictEqual(cached.version, 2, 'the cache kept the row read before the write landed')
    console.log('PASS a write in flight during a load is not returned or cached stale')
  } catch (error) {
    console.log(`FAIL a write in flight during a load is not returned or cached stale: ${error.message}`)
    process.exitCode = 1
  }
})()
