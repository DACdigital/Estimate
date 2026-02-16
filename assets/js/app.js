// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/estimate"
import topbar from "../vendor/topbar"
import Sortable from "sortablejs"
import SearchFocus from "./hooks/search_focus"
import AiEnhance from "./hooks/ai_enhance"

// Custom hooks
const Hooks = {
  ...colocatedHooks,
  SearchFocus,
  AiEnhance,

  JsonFileReader: {
    mounted() {
      this.el.addEventListener("change", (e) => {
        const file = e.target.files[0]
        if (!file) return

        const reader = new FileReader()
        reader.onload = (evt) => {
          this.pushEvent("json_file_uploaded", {content: evt.target.result})
          // Reset so same file can be re-selected
          this.el.value = ""
        }
        reader.readAsText(file)
      })
    }
  },

  // Generic div-based sortable for template editor
  TemplateSortable: {
    mounted() {
      const epicId = this.el.dataset.epicId

      new Sortable(this.el, {
        animation: 150,
        handle: ".drag-handle",
        draggable: "[data-id]",
        onEnd: () => {
          const ids = Array.from(this.el.querySelectorAll("[data-id]"))
            .map(el => el.dataset.id)

          if (epicId) {
            this.pushEvent("reorder_tasks", { epic_id: epicId, ids })
          } else {
            this.pushEvent("reorder_epics", { ids })
          }
        }
      })
    }
  },

  PriorityFilter: {
    mounted() {
      const key = `priorities:${this.el.dataset.estimationId}`
      const saved = localStorage.getItem(key)
      if (saved) {
        this.pushEvent("restore_priorities", { priorities: JSON.parse(saved) })
      }
      this.handleEvent("save_priorities", ({ priorities }) => {
        localStorage.setItem(key, JSON.stringify(priorities))
      })
    }
  },

  // Table-based sortable for estimator
  Sortable: {
    mounted() {
      const group = this.el.dataset.group

      if (group === "epics") {
        // Make epic rows sortable
        new Sortable(this.el, {
          animation: 150,
          handle: ".drag-handle",
          draggable: "tr[data-id]:not([data-epic-id])",
          onEnd: (evt) => {
            const ids = Array.from(this.el.querySelectorAll("tr[data-id]:not([data-epic-id])"))
              .map(row => row.dataset.id)
            this.pushEvent("reorder_epics", { ids })
          }
        })

        // Initialize task sorting for each epic
        this.initTaskSorting()
      }
    },

    updated() {
      // Re-initialize task sorting when DOM updates
      if (this.el.dataset.group === "epics") {
        this.initTaskSorting()
      }
    },

    initTaskSorting() {
      // Find all unique epic IDs
      const epicIds = new Set()
      this.el.querySelectorAll("tr[data-epic-id]").forEach(row => {
        epicIds.add(row.dataset.epicId)
      })

      // Create sortable for each epic's tasks
      epicIds.forEach(epicId => {
        const taskRows = this.el.querySelectorAll(`tr[data-epic-id="${epicId}"]`)
        if (taskRows.length === 0) return

        // Find the container (tbody) and the first task row
        const firstTask = taskRows[0]
        const container = firstTask.parentElement

        // Skip if already initialized
        if (container._sortableTask && container._sortableTask[epicId]) return

        if (!container._sortableTask) container._sortableTask = {}

        container._sortableTask[epicId] = new Sortable(container, {
          animation: 150,
          handle: ".drag-handle",
          draggable: `tr[data-epic-id="${epicId}"]`,
          filter: "tr:not([data-epic-id])", // Ignore epic header and subtotal rows
          onEnd: (evt) => {
            const ids = Array.from(container.querySelectorAll(`tr[data-epic-id="${epicId}"]`))
              .map(row => row.dataset.id)
            this.pushEvent("reorder_tasks", { epic_id: epicId, ids })
          }
        })
      })
    }
  }
}

// Handle clipboard copy
window.addEventListener("phx:copy_to_clipboard", (e) => {
  navigator.clipboard.writeText(e.detail.text)
})

// Handle file download from server push
window.addEventListener("phx:download_file", (e) => {
  const {content, filename, content_type} = e.detail
  const blob = new Blob([content], {type: content_type})
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
