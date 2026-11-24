// node tests/lock-state.test.js  -- exits non-zero on the first failed check.
// The cached `locked` binding once read true after an unlock, so a lock request before suspend
// answered "ok" and the machine slept unlocked. Every lock decision has to read the state afresh
// through currentlyLocked(), as Omarchy's own Service.qml does. Reads the source, since the session
// lock only changes state under a compositor.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")

assert.match(src, /function currentlyLocked\(\) \{\s*return lockRequested \|\| sessionLock\.locked \|\| sessionLock\.secure\s*\}/)
assert.match(src, /function lock\(\): string \{[\s\S]*?if \(!root\.currentlyLocked\(\) && !root\.beginLock\(\)\) return "failed"/)
assert.match(src, /function isLocked\(\): string \{\s*return root\.currentlyLocked\(\)/)
assert.match(src, /locked: root\.currentlyLocked\(\),/)
assert.match(src, /function finishUnlock\(\) \{\s*if \(!root\.currentlyLocked\(\)\) return/)
// the binding may still drive what the view draws, never a decision
const uses = src.match(/root\.locked\b/g) || []
assert.deepStrictEqual(uses, ["root.locked"], "root.locked is read only for the view's loadBackground")
assert.match(src, /bind\("loadBackground", function\(\) \{ return root\.locked \}\)/)

console.log("lock-state: all checks passed")
