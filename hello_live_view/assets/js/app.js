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


// Drag a window by its tab, the way you would on a real desktop.
//
// The server renders the authoritative position as an inline transform, so the
// first paint is already correct and this hook does nothing at rest. While a
// drag is in flight it writes the transform directly for a smooth 60fps, then
// hands the final coordinate back to the LiveView, which persists it. Should a
// diff land mid-drag, `updated()` re-asserts the in-flight position so the
// window cannot snap back under the pointer.
const WindowDrag = {
  mounted() {
    this.dragging = false
    this.handle = this.el.querySelector("[data-drag-handle]")
    if (!this.handle) return

    this.onPointerDown = (event) => {
      // Let the close and zoom boxes be clicked without starting a drag.
      if (event.button !== 0 || event.target.closest(".be-tab__button")) return

      const style = window.getComputedStyle(this.el)
      const matrix = new DOMMatrixReadOnly(style.transform)
      this.startX = matrix.m41
      this.startY = matrix.m42
      this.pointerX = event.clientX
      this.pointerY = event.clientY
      this.dragging = true
      this.moved = false
      this.el.classList.add("be-window--dragging")
      this.handle.setPointerCapture(event.pointerId)
      event.preventDefault()
    }

    this.onPointerMove = (event) => {
      if (!this.dragging) return
      const dx = event.clientX - this.pointerX
      const dy = event.clientY - this.pointerY
      if (!this.moved && Math.abs(dx) + Math.abs(dy) < 3) return
      this.moved = true
      this.applyPosition(this.startX + dx, this.startY + dy)
    }

    this.onPointerUp = (event) => {
      if (!this.dragging) return
      this.dragging = false
      this.el.classList.remove("be-window--dragging")
      if (this.handle.hasPointerCapture(event.pointerId)) {
        this.handle.releasePointerCapture(event.pointerId)
      }
      if (!this.moved) return
      this.pushEvent("move", {id: this.el.id, x: this.currentX, y: this.currentY})
    }

    this.handle.addEventListener("pointerdown", this.onPointerDown)
    this.handle.addEventListener("pointermove", this.onPointerMove)
    this.handle.addEventListener("pointerup", this.onPointerUp)
    this.handle.addEventListener("pointercancel", this.onPointerUp)
  },

  updated() {
    // A diff arrived mid-drag; keep the window under the pointer.
    if (this.dragging) this.applyPosition(this.currentX, this.currentY)
  },

  destroyed() {
    if (!this.handle) return
    this.handle.removeEventListener("pointerdown", this.onPointerDown)
    this.handle.removeEventListener("pointermove", this.onPointerMove)
    this.handle.removeEventListener("pointerup", this.onPointerUp)
    this.handle.removeEventListener("pointercancel", this.onPointerUp)
  },

  // Keep the window inside the desktop so it can never be dragged out of reach.
  applyPosition(x, y) {
    const desktop = this.el.offsetParent
    const maxX = desktop ? desktop.clientWidth - this.el.offsetWidth : x
    const maxY = desktop ? desktop.clientHeight - 34 : y

    this.currentX = Math.round(Math.min(Math.max(x, 0), Math.max(maxX, 0)))
    this.currentY = Math.round(Math.min(Math.max(y, 0), Math.max(maxY, 0)))
    this.el.style.transform = `translate3d(${this.currentX}px, ${this.currentY}px, 0)`
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: {WindowDrag},
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

