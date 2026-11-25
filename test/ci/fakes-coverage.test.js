// `npm run test:ci`: the live harness's server fakes cover every server slot.
//
// test/live/cis_test_providers/server/fakes.lua takes every capability slot so
// a live failure means the library failed, not the environment. A slot added to
// shared/registry.lua without a fake fails the live case "every slot resolves
// against the fakes" on every server; this pins the same rule off-server.

'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '..', '..')
const registry = fs.readFileSync(path.join(root, 'shared', 'registry.lua'), 'utf8')
const fakes = fs.readFileSync(path.join(root, 'test', 'live', 'cis_test_providers', 'server', 'fakes.lua'), 'utf8')

// Client-realm slots: the client fakes or a native fallback answer them.
const CLIENT_ONLY = new Set(['doorsClient', 'ui'])

// slot -> [method] from CisRegistry.SLOTS.
function contractSlots() {
  const start = registry.indexOf('CisRegistry.SLOTS = {')
  assert.ok(start >= 0, 'CisRegistry.SLOTS found')
  const slots = {}
  let current = null
  for (const line of registry.slice(start).split('\n').slice(1)) {
    if (/^}/.test(line)) break
    const slot = line.match(/^ {4}(\w+) = \{/)
    if (slot) { current = slots[slot[1]] = []; continue }
    const m = line.match(/^ {8}(\w+) = /)
    if (m && current) current.push(m[1])
  }
  return slots
}

// The body of `local <name> = { ... }` at column 0, up to its closing `}`.
function fakeTable(name) {
  const m = fakes.match(new RegExp('^local ' + name + ' = \\{\\n([\\s\\S]*?)^\\}', 'm'))
  return m ? m[1] : null
}

test('every server slot has a fake answering its whole contract', () => {
  const slots = contractSlots()
  assert.ok(Object.keys(slots).length >= 10, 'the contract parse found the slots')
  const providers = fakeTable('PROVIDERS')
  assert.ok(providers, 'PROVIDERS table found')
  const listed = new Set([...providers.matchAll(/^ {4}(\w+) = \w+,/gm)].map((m) => m[1]))

  const missing = []
  for (const [slot, methods] of Object.entries(slots)) {
    if (CLIENT_ONLY.has(slot)) continue
    if (!listed.has(slot)) { missing.push(slot); continue }
    const body = fakeTable(slot) || ''
    for (const name of methods) {
      if (!new RegExp('^ {4}' + name + ' = method\\(', 'm').test(body)) missing.push(slot + '.' + name)
    }
  }
  assert.deepEqual(missing, [], 'slots or methods without a fake')
})
