// Settings for the Lumon lock and the MDR screen.
//
// They live inline on this plugin's entry in ~/.config/omarchy/shell.json, the way Omarchy
// stores every plugin's settings:
//
//   "plugins": [ { "id": "lumon.lock", "displayOffSeconds": 900, "crt": "subtle" } ]
//
// Anything missing, mistyped or out of range falls back to its default, so a bad edit to
// shell.json can never break the lock. Used from QML (Service.qml, screensaver/shell.qml) and
// from node (tests/settings.test.js).

var defaults = {
  displayOffSeconds: 600,     // locked: turn the displays off after this long without input
  hidePointerSeconds: 3,      // locked: hide a still pointer after this long; 0 leaves it alone
  loginTimeoutSeconds: 10,    // locked: go back to the idle screen after this long with nothing typed
  idleScreen: "mdr",          // locked and idle: "mdr" shows the MDR screen, "login" the login
  crt: "full",                // CRT tube: "full", "subtle" or "off"
  clusters: 3,                // hidden "scary" number clusters on the MDR screen
  files: ["Cold Harbor", "Siena", "Cocoa", "Dranesville", "Tumwater", "Allentown"]
}

var limits = {
  displayOffSeconds: [5, 86400],
  hidePointerSeconds: [0, 600],
  loginTimeoutSeconds: [3, 600],
  clusters: [1, 8]
}

var choices = {
  idleScreen: ["mdr", "login"],
  crt: ["full", "subtle", "off"]
}

var crtStrengths = { off: 0, subtle: 0.5, full: 1 }

function pick(entry, key) {
  var value = entry ? entry[key] : undefined
  if (limits[key]) {
    var n = Number(value)
    if (value === null || value === undefined || value === "" || typeof value === "boolean" || !isFinite(n))
      return defaults[key]
    return Math.min(limits[key][1], Math.max(limits[key][0], Math.round(n)))
  }
  if (choices[key]) return choices[key].indexOf(value) !== -1 ? value : defaults[key]
  if (key === "files") {
    if (!Array.isArray(value)) return defaults.files.slice()
    var names = value.filter(function (v) { return typeof v === "string" && v.trim().length > 0 })
      .map(function (v) { return v.trim().slice(0, 40) })
    return names.length > 0 ? names : defaults.files.slice()
  }
  return defaults[key]
}

// Resolve one plugin entry ({ id, ...settings }) into a full, valid settings object.
function resolve(entry) {
  var out = {}
  for (var key in defaults) out[key] = pick(entry, key)
  out.crtStrength = crtStrengths[out.crt]
  return out
}

// Find this plugin's entry in a parsed shell.json and resolve it.
function fromShellConfig(config, pluginId) {
  var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
  var entry = null
  for (var i = 0; i < plugins.length; i++) {
    if (plugins[i] && typeof plugins[i] === "object" && plugins[i].id === pluginId) { entry = plugins[i]; break }
  }
  return resolve(entry)
}

// Parse shell.json text; any parse error gives the defaults.
function fromShellJson(text, pluginId) {
  var config = null
  try { config = JSON.parse(text) } catch (e) { config = null }
  return fromShellConfig(config, pluginId)
}

if (typeof module !== "undefined") module.exports = { defaults: defaults, resolve: resolve, fromShellConfig: fromShellConfig, fromShellJson: fromShellJson }
