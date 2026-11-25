// Stage 1.5, part 2: check that every native is called in a realm where it exists.
//
// The defect this catches is a client-only native on the server. server/sync.lua calls
// RequestModel, which is a client-only native. On a real server that is nil, and
// `nil(...)` raises in the middle of the sync path where nobody is watching.
// Nothing in the test suite noticed, because the unit stubs hand the server test
// VM a permissive set of natives that the real server VM does not have.
//
// THE RULE.
//   server/*.lua   may call server and shared natives. Never client.
//   client/*.lua   may call client and shared natives. Never server.
//   shared/*, init.lua   may call a realm-only native ONLY inside an
//                         IsDuplicityVersion() or IS_SERVER branch, and only
//                         when it is on the reviewed allow-list below.
//   An unknown PascalCase call FAILS. That is deliberate: a misspelled native is
//   a runtime nil-index in a different subsystem entirely, and the alternative
//   is a warning nobody reads.
//
// knownViolations is the escape hatch for defects already open at the baseline.
// It starts with exactly the one the plan names. A new entry is a claim that a
// bug is acceptable, and it has to be emptied by the task that fixes it -- so it
// is printed in full on every run rather than silently tolerated.

const fs = require('fs')
const path = require('path')
const { realmOverrides } = require('./natives/realm-guard.js')

const root = path.join(__dirname, '..')
const nativesDoc = JSON.parse(fs.readFileSync(path.join(root, 'tools', 'natives', 'natives.json'), 'utf8'))
// CIS_REALMS_RUNTIME points the check at another runtime list; the tool
// self-test uses it to prove the override guard below fails the build.
const runtimePath = process.env.CIS_REALMS_RUNTIME || path.join(root, 'tools', 'natives', 'runtime.json')
const runtime = JSON.parse(fs.readFileSync(runtimePath, 'utf8'))
const libGlobalsDoc = JSON.parse(fs.readFileSync(path.join(root, 'tools', 'natives', 'lib-globals.json'), 'utf8'))

// name -> realm.
//
// ORDER MATTERS, and getting it wrong manufactures violations. The runtime list
// is consulted FIRST and overwrites: Wait, GetGameTimer and GetPlayerName all
// appear in the GTA database as client-only game natives, but CfxLua provides
// all three on the server VM too, and calling them from a server file is
// correct and common. If the database won, this checker would report five
// separate false violations on the security rate limiter.
const REALMS = new Map()
const RUNTIME_SET = new Set()
for (const [name, info] of Object.entries(nativesDoc.natives)) REALMS.set(name, info.realm)
for (const [realm, names] of Object.entries(runtime)) {
  if (realm === '$comment') continue
  for (const n of names) { RUNTIME_SET.add(n); REALMS.set(n, realm) }
}

// The library's own globals. Each is defined by the files that load in its own
// realm, so it is legal everywhere it exists and is never a realm violation --
// it is simply not a native, and must not be reported as an unknown one.
const LIB_GLOBALS = new Set(Object.keys(libGlobalsDoc.globals))

// Defects already open at the baseline, allowed until the task that owns them
// lands. EMPTY, and that is the point: it held the three model-request natives
// on one server line -- RequestModel, HasModelLoaded and
// SetModelAsNoLongerNeeded, all `apiset: client`, all in the same function, all
// asking a server for something only a client has. The networked path is now
// created with the server RPC natives, so nothing is left to allow.
//
// An entry here is a promise that the defect is being fixed and by which task.
// An empty list is the stronger statement: no shipped file calls a native in a
// realm that does not have it, so a violation here is a NEW one and the build
// fails on it.
const knownViolations = []

// Calls to names that are not natives, not runtime functions and not the
// library's own globals. Each one is a `nil(...)` the first time that line
// runs. They are listed rather than fixed here because this task builds a
// checker; the fixes belong with the product change that owns them.
const knownUnknownGlobals = [
  {
    file: 'client/utils.lua',
    name: 'GetGameplayCamCoords',
    defect: 'the native is GET_GAMEPLAY_CAM_COORD (singular); there is no plural form',
  },
  {
    file: 'client/utils.lua',
    name: 'DrawText',
    defect: 'no such native; screen text is drawn with BeginTextCommandDisplayText / EndTextCommandDisplayText',
  },
]

// Shared files may branch on the realm. A realm-only native outside one of these
// is a latent bug, because the branch that needs it is not the branch that runs.
const REALM_BRANCHES = /(IsDuplicityVersion\(\)|IS_SERVER\b|not\s+IsServer|IsServerRealm)/

// The end of a long bracket `[==[ ... ]==]` opening at `at`, or -1 when `at` does
// not open one. The level (count of `=`) must match on both sides.
function longBracketEnd(src, at) {
  let j = at + 1
  let level = ''
  while (j < src.length && src[j] === '=') { level += '='; j++ }
  if (src[j] !== '[') return -1
  const close = ']' + level + ']'
  const end = src.indexOf(close, j + 1)
  return end === -1 ? src.length : end + close.length
}

function stripNonCode(src) {
  let out = ''
  let i = 0
  const n = src.length
  while (i < n) {
    const c = src[i]
    if (c === '-' && src[i + 1] === '-' && src[i + 2] === '[') {
      const stop = longBracketEnd(src, i + 2)
      if (stop !== -1) {
        out += src.slice(i, stop).replace(/[^\n]/g, ' ')
        i = stop
        continue
      }
    }
    // A long string is a string: SQL in one (`VARCHAR(64)`) is not a call. Its
    // first bracket stays, like a quote, so offsets and the string start survive.
    if (c === '[') {
      const stop = longBracketEnd(src, i)
      if (stop !== -1) {
        out += '[' + src.slice(i + 1, stop).replace(/[^\n]/g, ' ')
        i = stop
        continue
      }
    }
    if (c === '-' && src[i + 1] === '-') {
      const end = src.indexOf('\n', i)
      const stop = end === -1 ? n : end
      out += ' '.repeat(stop - i)
      i = stop
      continue
    }
    if (c === '"' || c === "'") {
      const quote = c
      let j = i + 1
      while (j < n) {
        if (src[j] === '\\') { j += 2; continue }
        if (src[j] === quote || src[j] === '\n') break
        j++
      }
      out += quote + ' '.repeat(Math.max(0, Math.min(j, n - 1) - i - 1)) + (src[j] === quote ? quote : '')
      i = j + 1
      continue
    }
    out += c
    i++
  }
  return out
}

const GLOBAL_CALL = /(?:^|[^\w_.:\]"'])([A-Z][A-Za-z0-9_]*)\s*\(/g
const LOCAL_DECL = /(?:^|[^\w_.])local\s+(?:function\s+)?([A-Z][A-Za-z0-9_]*)/g

function shippedFiles(base = root) {
  const manifest = fs.readFileSync(path.join(base, 'fxmanifest.lua'), 'utf8')
  const out = []
  for (const [realm, kw] of [['shared', 'shared_scripts'], ['client', 'client_scripts'], ['server', 'server_scripts']]) {
    const re = new RegExp(kw + '\\s*\\{([^}]*)\\}', 'g')
    let m
    while ((m = re.exec(manifest)) !== null) {
      const str = /(['"])((?:\\.|(?!\1)[^\\])*)\1/g
      let s
      while ((s = str.exec(m[1])) !== null) {
        const v = s[2]
        if (v.startsWith('@') || v.startsWith('/')) continue
        if (!fs.existsSync(path.join(base, v))) continue
        out.push({ realm, file: v })
      }
    }
  }
  // CONSUMER-LOADED CLIENT FILES. client/core/*.lua that cis_libs does not run
  // itself are listed in `files {}`, not `client_scripts`, and init.lua loads
  // them into a CONSUMER's client VM. They are client code all the same, so
  // they are checked (and their natives indexed) as the client realm -- a file
  // that escaped the realm rule because of which block lists it would be the
  // first place a server-only native could hide.
  const filesBlock = /^\s*files\s*\{([^}]*)\}/m.exec(manifest)
  if (filesBlock) {
    const seen = new Set(out.map(f => f.file))
    const str = /(['"])((?:\\.|(?!\1)[^\\])*)\1/g
    let s
    const body = filesBlock[1].replace(/--[^\n]*/g, '')
    while ((s = str.exec(body)) !== null) {
      const v = s[2]
      if (!/^client\/.*\.lua$/.test(v) || seen.has(v)) continue
      if (!fs.existsSync(path.join(base, v))) continue
      out.push({ realm: 'client', file: v })
    }
  }
  return out
}

// THE LIVE HARNESS. test/live/* resources are not shipped, but a realm bug
// there hides a check rather than breaking a player: cis_test read and restored
// the routing bucket on the client, where those server natives are nil, so its
// "player is back where the harness found them" case skipped the field on
// every run. Realm violations only: the harness defines its own globals, and
// lint already reports an undefined one. A native named in a STRING counts
// too, because the harness calls optional natives by name (`read('Name', ...)`).
const STRING_NAME = /'([A-Z][A-Za-z0-9_]*)'|"([A-Z][A-Za-z0-9_]*)"/g

function harnessViolations() {
  // CIS_REALMS_LIVE points the pass at another folder of resources; the tool
  // self-test uses it to prove a client-side server native fails the build.
  const live = process.env.CIS_REALMS_LIVE || path.join(root, 'test', 'live')
  const realms = new Map()
  for (const [name, info] of Object.entries(nativesDoc.natives)) realms.set(name, info.realm)
  for (const [name, info] of Object.entries(nativesDoc.harness || {})) realms.set(name, info.realm)
  for (const [realm, names] of Object.entries(runtime)) {
    if (realm === '$comment') continue
    for (const n of names) realms.set(n, realm)
  }

  const files = []
  const out = []
  if (!fs.existsSync(live)) return { files, out }
  for (const res of fs.readdirSync(live).sort()) {
    const dir = path.join(live, res)
    if (!fs.existsSync(path.join(dir, 'fxmanifest.lua'))) continue
    for (const { realm, file } of shippedFiles(dir)) {
      const rel = path.posix.join('test/live', res, file)
      files.push(rel)
      const raw = fs.readFileSync(path.join(dir, file), 'utf8')
      const code = stripNonCode(raw)
      const locals = new Set()
      LOCAL_DECL.lastIndex = 0
      let lm
      while ((lm = LOCAL_DECL.exec(code)) !== null) locals.add(lm[1])
      const lines = code.split('\n')
      const inRealmBranch = lines.map(line => REALM_BRANCHES.test(line))

      const hits = []
      GLOBAL_CALL.lastIndex = 0
      let m
      while ((m = GLOBAL_CALL.exec(code)) !== null) hits.push({ name: m[1], index: m.index })
      // stripNonCode keeps every offset and keeps a string's quotes, so a
      // string in code starts with a quote at the same offset in `code`; one
      // inside a comment starts with a blank there and is skipped.
      STRING_NAME.lastIndex = 0
      while ((m = STRING_NAME.exec(raw)) !== null) {
        if (code[m.index] === raw[m.index]) hits.push({ name: m[1] || m[2], index: m.index })
      }

      const seen = new Set()
      for (const { name, index } of hits) {
        if (locals.has(name) || seen.has(name)) continue
        const nativeRealm = realms.get(name)
        if (nativeRealm === undefined || nativeRealm === 'std' || nativeRealm === 'shared') continue
        if (nativeRealm === realm) continue
        const lineNo = code.slice(0, index).split('\n').length - 1
        if (realm === 'shared' && inRealmBranch.slice(0, lineNo + 1).some(Boolean)) continue
        seen.add(name)
        out.push({ file: rel, realm, name, nativeRealm, line: lineNo + 1 })
      }
    }
  }
  return { files, out }
}

// CIS_REALMS_ROOT points the shipped-file pass at another resource; the tool
// self-test uses it to prove an unknown call fails and SQL in a long string does not.
const shippedRoot = process.env.CIS_REALMS_ROOT || root

function main() {
  const files = shippedFiles(shippedRoot)
  const violations = []
  const unknown = []

  for (const { realm, file } of files) {
    const raw = fs.readFileSync(path.join(shippedRoot, file), 'utf8')
    const code = stripNonCode(raw)
    const locals = new Set()
    LOCAL_DECL.lastIndex = 0
    let lm
    while ((lm = LOCAL_DECL.exec(code)) !== null) locals.add(lm[1])

    // A shared file that branches on the realm gets its lines tagged, so a
    // realm-only call on the right side of an IsDuplicityVersion() test is not
    // reported. Done per line because the branch is a statement, not a file.
    const lines = code.split('\n')
    const inRealmBranch = lines.map(line => REALM_BRANCHES.test(line))

    GLOBAL_CALL.lastIndex = 0
    let m
    const seenHere = new Set()
    while ((m = GLOBAL_CALL.exec(code)) !== null) {
      const name = m[1]
      if (locals.has(name) || seenHere.has(name)) continue
      seenHere.add(name)

      const nativeRealm = REALMS.get(name)
      if (nativeRealm === undefined) {
        // The library's own globals are legal wherever they are defined, so
        // they resolve here rather than in the native table.
        if (LIB_GLOBALS.has(name)) continue
        unknown.push({ file, realm, name }); continue
      }
      if (nativeRealm === 'std' || nativeRealm === 'shared') continue

      // The line this call sits on, and whether a realm branch governs it.
      const upto = code.slice(0, m.index)
      const lineNo = upto.split('\n').length - 1
      const guarded = realm === 'shared' && (inRealmBranch[lineNo] || inRealmBranch.slice(0, lineNo + 1).some(Boolean))
      if (guarded) continue

      if (nativeRealm === realm) continue
      violations.push({ file, realm, name, nativeRealm })
    }
  }

  const knownSet = new Set(knownViolations.map(v => v.file + '|' + v.name))
  const knownUnknownSet = new Set(knownUnknownGlobals.map(v => v.file + '|' + v.name))
  const real = violations.filter(v => !knownSet.has(v.file + '|' + v.name))
  const known = violations.filter(v => knownSet.has(v.file + '|' + v.name))
  const realUnknown = unknown.filter(u => !knownUnknownSet.has(u.file + '|' + u.name))
  const knownUnknown = unknown.filter(u => knownUnknownSet.has(u.file + '|' + u.name))

  console.log('realm check: ' + files.length + ' shipped files, ' +
    nativesDoc.counts.nativesUsed + ' natives, ' + RUNTIME_SET.size + ' runtime functions')

  if (known.length) {
    console.log('\nKNOWN VIOLATIONS (open defects, allowed by the reviewed list):')
    for (const v of known) {
      const meta = knownViolations.find(k => k.file === v.file && k.name === v.name)
      console.log('  ' + v.file + ': ' + v.name + ' -- ' + (meta ? meta.defect : 'listed'))
    }
    console.log('  ' + known.length + ' known, ' + knownViolations.length + ' on the list')
  } else {
    console.log('known violations: none on the list are still present')
  }

  let failed = false
  if (real.length) {
    failed = true
    console.log('\nREALM VIOLATIONS (these fail the build):')
    for (const v of real) {
      console.log('  ' + v.file + ':' + v.realm + ' calls ' + v.name +
        ' which only exists on the ' + v.nativeRealm + ' realm')
    }
    console.log('  ' + real.length + ' total')
  } else {
    console.log('realm violations: 0')
  }

  if (knownUnknown.length) {
    console.log('\nKNOWN UNDEFINDED CALLS (open defects, listed with a reason):')
    for (const u of knownUnknown) {
      const meta = knownUnknownGlobals.find(k => k.file === u.file && k.name === u.name)
      console.log('  ' + u.file + ': ' + u.name + ' -- ' + (meta ? meta.defect : 'listed'))
    }
    console.log('  ' + knownUnknown.length + ' known, ' + knownUnknownGlobals.length + ' on the list')
  }

  // Checked against natives.json, which holds every native shipped code uses:
  // those are the names where an override can change a verdict above.
  // build-natives.js checks the full published databases when it regenerates.
  const overrides = realmOverrides(runtime, name => {
    const info = nativesDoc.natives[name]
    return info ? info.realm : undefined
  })
  if (overrides.length) {
    failed = true
    console.log('\nRUNTIME OVERRIDES (runtime.json replaces a published realm):')
    for (const o of overrides) {
      console.log('  ' + o.name + ': listed ' + o.listed + ', published ' + o.published)
    }
    console.log('  Delete the row; the realm comes from natives.json. Fix any call it was hiding.')
  }

  const harness = harnessViolations()
  if (harness.out.length) {
    failed = true
    console.log('\nHARNESS REALM VIOLATIONS (test/live; these fail the build):')
    for (const v of harness.out) {
      console.log('  ' + v.file + ':' + v.line + ' (' + v.realm + ') uses ' + v.name +
        ' which only exists on the ' + v.nativeRealm + ' realm')
    }
  } else {
    console.log('harness realm violations: 0 in ' + harness.files.length + ' test/live files')
  }

  if (realUnknown.length) {
    failed = true
    console.log('\nUNKNOWN GLOBAL CALLS (a misspelled native is a nil-index elsewhere):')
    for (const u of realUnknown) console.log('  ' + u.file + ' (' + u.realm + '): ' + u.name)
    console.log('  ' + realUnknown.length + ' total')
    console.log('  If one is a real CfxLua function, add it to tools/natives/runtime.json.')
    console.log('  If it is a misspelling, fix the call. Do not silence it here.')
  } else {
    console.log('unknown globals: 0')
  }

  process.exit(failed ? 1 : 0)
}

main()