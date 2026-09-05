function clampSeconds(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

function formatDuration(seconds) {
  var n = clampSeconds(seconds, 0)
  if (n <= 0) return "Never"
  if (n < 60) return n + "s"
  if (n < 3600) return Math.round(n / 60) + "m"
  var hours = n / 3600
  var rounded = Math.round(hours * 10) / 10
  return (rounded % 1 === 0 ? rounded.toFixed(0) : rounded.toFixed(1)) + "h"
}

var screensaverPresets = [
  { label: "1m", seconds: 60 },
  { label: "2m", seconds: 120 },
  { label: "5m", seconds: 300 },
  { label: "10m", seconds: 600 },
  { label: "15m", seconds: 900 },
  { label: "30m", seconds: 1800 }
]

var lockPresets = [
  { label: "2m", seconds: 120 },
  { label: "5m", seconds: 300 },
  { label: "10m", seconds: 600 },
  { label: "15m", seconds: 900 },
  { label: "30m", seconds: 1800 },
  { label: "1h", seconds: 3600 }
]

var suspendPresets = [
  { label: "Never", seconds: 0 },
  { label: "10m", seconds: 600 },
  { label: "15m", seconds: 900 },
  { label: "30m", seconds: 1800 },
  { label: "1h", seconds: 3600 },
  { label: "2h", seconds: 7200 }
]

// Index of the preset whose seconds value is closest to `seconds`. Used to
// position a slider from the committed config value, which is always one of
// this list's own preset seconds (sliders only ever write preset values back).
function nearestIndexForSeconds(presets, seconds) {
  var target = clampSeconds(seconds, 0)
  var bestIndex = 0
  var bestDiff = Infinity
  for (var i = 0; i < presets.length; i++) {
    var diff = Math.abs(presets[i].seconds - target)
    if (diff < bestDiff) {
      bestDiff = diff
      bestIndex = i
    }
  }
  return bestIndex
}

// Index of the smallest preset whose seconds strictly exceeds `minSeconds`,
// or the last (largest) preset if every one of them is <= minSeconds. A
// preset of 0 ("Never") never satisfies "> minSeconds" for a non-negative
// threshold, so it is skipped without any special-casing.
function indexAboveSeconds(presets, minSeconds) {
  for (var i = 0; i < presets.length; i++) {
    if (presets[i].seconds > minSeconds) return i
  }
  return presets.length - 1
}

if (typeof module !== "undefined") {
  module.exports = {
    clampSeconds: clampSeconds,
    formatDuration: formatDuration,
    screensaverPresets: screensaverPresets,
    lockPresets: lockPresets,
    suspendPresets: suspendPresets,
    nearestIndexForSeconds: nearestIndexForSeconds,
    indexAboveSeconds: indexAboveSeconds
  }
}
