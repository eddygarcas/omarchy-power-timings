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

if (typeof module !== "undefined") {
  module.exports = {
    clampSeconds: clampSeconds,
    formatDuration: formatDuration,
    screensaverPresets: screensaverPresets,
    lockPresets: lockPresets,
    suspendPresets: suspendPresets
  }
}
