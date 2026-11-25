// runtime.json must never override a published realm.
//
// check-realms.js reads natives.json first and runtime.json second, and the
// second overwrites. So a runtime row that names a published native REPLACES
// the realm natives_cfx.json gives it. Fifteen such rows once sat in the file:
// PlayerId listed shared (it is client), ExecuteCommand listed server (it is
// shared), SaveResourceFile listed shared (it is server), and so on. Each one
// could pass a call in a realm that does not have the native, which is the
// exact defect the realm check exists to catch.
//
// A runtime row that AGREES with the published realm changes no verdict and is
// allowed. A row that disagrees fails the build, except the three below.

// CfxLua provides these on both VMs although the databases say otherwise: Wait
// is the scheduler's (GTA lists WAIT as client), and the server runtime
// implements GetGameTimer and GetPlayerName itself.
const RUNTIME_OVER_NATIVE = new Set(['Wait', 'GetGameTimer', 'GetPlayerName'])

// runtime: the parsed runtime.json. publishedRealm: name -> published realm, or
// undefined when the name is not a published native. Returns every row that
// overrides a published realm and is not one of the exceptions.
function realmOverrides(runtime, publishedRealm) {
  const out = []
  for (const [listed, names] of Object.entries(runtime)) {
    if (listed === '$comment' || listed === 'std') continue
    for (const name of names) {
      if (RUNTIME_OVER_NATIVE.has(name)) continue
      const published = publishedRealm(name)
      if (published !== undefined && published !== listed) out.push({ name, listed, published })
    }
  }
  return out
}

module.exports = { RUNTIME_OVER_NATIVE, realmOverrides }
