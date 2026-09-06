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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"


// Move and resize a window, entirely client-side while the pointer is down.
//
// The server renders the authoritative geometry as inline style, so the first
// paint is already correct and this hook does nothing at rest. During a gesture
// it writes style directly for a smooth 60fps, then hands the final numbers to
// the LiveView, which persists them. If a diff lands mid-gesture, `updated()`
// re-asserts what the pointer is doing so nothing snaps out from under it.
const WindowFrame = {
  mounted() {
    this.gesture = null
    this.dragHandle = this.el.querySelector("[data-drag-handle]")
    this.resizeHandle = this.el.querySelector("[data-resize-handle]")

    this.onPointerDown = (event) => {
      if (event.button !== 0) return
      const resizing = this.resizeHandle && this.resizeHandle.contains(event.target)
      // Let the close and zoom boxes be clicked without starting a drag.
      if (!resizing && event.target.closest(".be-tab__button")) return

      const rect = this.el.getBoundingClientRect()
      const matrix = new DOMMatrixReadOnly(window.getComputedStyle(this.el).transform)
      this.gesture = {
        type: resizing ? "resize" : "move",
        pointerX: event.clientX,
        pointerY: event.clientY,
        startX: matrix.m41,
        startY: matrix.m42,
        startW: rect.width,
        startH: rect.height,
        moved: false
      }
      this.currentX = matrix.m41
      this.currentY = matrix.m42
      this.currentW = Math.round(rect.width)
      this.currentH = Math.round(rect.height)
      this.el.classList.add(resizing ? "be-window--resizing" : "be-window--dragging")
      event.currentTarget.setPointerCapture(event.pointerId)
      event.preventDefault()
    }

    this.onPointerMove = (event) => {
      if (!this.gesture) return
      const dx = event.clientX - this.gesture.pointerX
      const dy = event.clientY - this.gesture.pointerY
      if (!this.gesture.moved && Math.abs(dx) + Math.abs(dy) < 3) return
      this.gesture.moved = true
      this.apply(dx, dy)
    }

    this.onPointerUp = (event) => {
      if (!this.gesture) return
      const {type, moved} = this.gesture
      this.gesture = null
      this.el.classList.remove("be-window--dragging", "be-window--resizing")
      if (event.currentTarget.hasPointerCapture(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId)
      }
      if (!moved) return
      if (type === "resize") {
        this.pushEvent("resize", {id: this.el.id, w: this.currentW, h: this.currentH})
      } else {
        this.pushEvent("move", {id: this.el.id, x: this.currentX, y: this.currentY})
      }
    }

    for (const handle of [this.dragHandle, this.resizeHandle]) {
      if (!handle) continue
      handle.addEventListener("pointerdown", this.onPointerDown)
      handle.addEventListener("pointermove", this.onPointerMove)
      handle.addEventListener("pointerup", this.onPointerUp)
      handle.addEventListener("pointercancel", this.onPointerUp)
    }
  },

  updated() {
    if (this.gesture) this.apply(0, 0, true)
  },

  destroyed() {
    for (const handle of [this.dragHandle, this.resizeHandle]) {
      if (!handle) continue
      handle.removeEventListener("pointerdown", this.onPointerDown)
      handle.removeEventListener("pointermove", this.onPointerMove)
      handle.removeEventListener("pointerup", this.onPointerUp)
      handle.removeEventListener("pointercancel", this.onPointerUp)
    }
  },

  // Everything stays inside the desktop, so a window can never be pushed or
  // shrunk out of reach.
  apply(dx, dy, reassert = false) {
    const desktop = this.el.offsetParent
    const maxW = desktop ? desktop.clientWidth : Infinity
    const maxH = desktop ? desktop.clientHeight : Infinity

    if (this.gesture.type === "resize") {
      if (!reassert) {
        this.currentW = Math.round(clamp(this.gesture.startW + dx, 260, maxW - this.currentX))
        this.currentH = Math.round(clamp(this.gesture.startH + dy, 140, maxH - this.currentY))
      }
      this.el.style.width = `${this.currentW}px`
      this.el.style.height = `${this.currentH}px`
      this.el.classList.add("be-window--sized")
    } else {
      if (!reassert) {
        this.currentX = Math.round(clamp(this.gesture.startX + dx, 0, Math.max(maxW - this.el.offsetWidth, 0)))
        this.currentY = Math.round(clamp(this.gesture.startY + dy, 0, Math.max(maxH - 34, 0)))
      }
      this.el.style.transform = `translate3d(${this.currentX}px, ${this.currentY}px, 0)`
    }
  }
}

const clamp = (value, low, high) => Math.min(Math.max(value, low), Math.max(high, low))

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: {WindowFrame},
  params: {_csrf_token: csrfToken}
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

