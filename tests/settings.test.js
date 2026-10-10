// node tests/settings.test.js  -- exits non-zero on the first failed check.
const assert = require("assert")
const S = require("../Settings.js")
const id = "lumon.lock"

// no entry, no file, garbage file: all defaults
assert.deepStrictEqual(S.fromShellConfig(null, id), S.resolve(null))
assert.strictEqual(S.fromShellJson("{not json", id).displayOffSeconds, 600)
assert.strictEqual(S.fromShellJson("", id).crt, "full")

// reads only this plugin's entry
const cfg = { plugins: [{ id: "other", displayOffSeconds: 30 }, { id, displayOffSeconds: 900, crt: "subtle" }] }
const s = S.fromShellConfig(cfg, id)
assert.strictEqual(s.displayOffSeconds, 900)
assert.strictEqual(s.crt, "subtle")
assert.strictEqual(s.crtStrength, 0.5)

// numbers: clamped, rounded, wrong types fall back
const r = (e) => S.resolve(Object.assign({ id }, e))
assert.strictEqual(r({ displayOffSeconds: 1 }).displayOffSeconds, 5)
assert.strictEqual(r({ displayOffSeconds: 1e9 }).displayOffSeconds, 86400)
assert.strictEqual(r({ displayOffSeconds: "120" }).displayOffSeconds, 120)
assert.strictEqual(r({ displayOffSeconds: "soon" }).displayOffSeconds, 600)
assert.strictEqual(r({ displayOffSeconds: true }).displayOffSeconds, 600)
assert.strictEqual(r({ displayOffSeconds: null }).displayOffSeconds, 600)
assert.strictEqual(r({ hidePointerSeconds: 0 }).hidePointerSeconds, 0)
assert.strictEqual(r({ clusters: 2.6 }).clusters, 3)
assert.strictEqual(r({ clusters: 99 }).clusters, 8)

// choices: unknown values fall back
assert.strictEqual(r({ idleScreen: "login" }).idleScreen, "login")
assert.strictEqual(r({ idleScreen: "LOGIN" }).idleScreen, "mdr")
assert.strictEqual(r({ crt: "off" }).crtStrength, 0)

// files: strings only, trimmed and capped; empty or wrong falls back
assert.deepStrictEqual(r({ files: [" Lumon ", 3, "", "x".repeat(80)] }).files, ["Lumon", "x".repeat(40)])
assert.deepStrictEqual(r({ files: [] }).files, S.defaults.files)
assert.deepStrictEqual(r({ files: "Siena" }).files, S.defaults.files)

// defaults are never shared, so a caller can't mutate them
r({}).files.push("oops")
assert.strictEqual(S.defaults.files.indexOf("oops"), -1)

console.log("settings: all checks passed")
