// Suppresses the settings rail's entry animation on settings-to-settings
// navigation. Live navigation between settings LiveViews replaces the main
// container, so #settings-rail is destroyed and re-created on every rail
// click — without this the CSS entry animation would replay each time.
//
// Hook callback order during the swap is mounted(new) before destroyed(old),
// so a destroyed-timestamp cannot signal the swap in time. Instead we record
// where each live navigation started: phx:page-loading-start fires before the
// container swap, while window.location still points at the page being left.
// window state survives live navigation; a full page load resets it, which is
// exactly the "fresh entry" case that should animate.
const SETTINGS_PATH = /\/settings(\/|$)/

window.addEventListener("phx:page-loading-start", (info) => {
  if (info.detail && info.detail.kind === "redirect") {
    window.__settingsRailNavFrom = window.location.pathname
  }
})

const SettingsRail = {
  mounted() {
    const from = window.__settingsRailNavFrom
    if (from && SETTINGS_PATH.test(from)) {
      this.el.style.animation = "none"
    }
  },
}

export default SettingsRail
