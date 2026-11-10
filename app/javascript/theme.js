// Runs before first paint. Same storage key and modes as the Kilat dashboard.
(() => {
  const system = window.matchMedia("(prefers-color-scheme: dark)")
  const modes = ["light", "dark", "system"]
  let saved = "system"
  try { saved = localStorage.getItem("kilat-theme") || "system" } catch (_) {}
  if (!modes.includes(saved)) saved = "system"

  function apply(mode = saved) {
    saved = modes.includes(mode) ? mode : "system"
    const root = document.documentElement
    root.dataset.theme = saved === "system" ? (system.matches ? "dark" : "light") : saved
    root.dataset.themeMode = saved
    const next = modes[(modes.indexOf(saved) + 1) % modes.length]
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      button.setAttribute("aria-label", `Appearance: ${saved}. Switch to ${next}`)
      button.setAttribute("title", `Appearance: ${saved}`)
    })
  }

  apply()
  system.addEventListener("change", () => apply())
  document.addEventListener("DOMContentLoaded", () => apply())
  document.addEventListener("turbo:load", () => apply())
  document.addEventListener("click", (event) => {
    if (!event.target.closest("[data-theme-toggle]")) return
    apply(modes[(modes.indexOf(saved) + 1) % modes.length])
    try { localStorage.setItem("kilat-theme", saved) } catch (_) {}
  })
})()
