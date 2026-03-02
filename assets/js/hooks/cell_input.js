const CellInput = {
  mounted() {
    this._eventFired = false
    this.el.select()

    const saveEvent = this.el.dataset.saveEvent

    this._handleKeydown = (e) => {
      if (e.key === "Escape") {
        e.preventDefault()
        this._eventFired = true
        this.pushEvent("cancel_edit", {})
      } else if (e.key === "Enter") {
        e.preventDefault()
        this._eventFired = true
        this.pushEvent(saveEvent, {...this._params(), value: this.el.value})
      }
    }

    this._handleBlur = () => {
      if (!this._eventFired) {
        this.pushEvent(saveEvent, {...this._params(), value: this.el.value})
      }
    }

    this.el.addEventListener("keydown", this._handleKeydown)
    this.el.addEventListener("blur", this._handleBlur)
  },

  destroyed() {
    this.el.removeEventListener("keydown", this._handleKeydown)
    this.el.removeEventListener("blur", this._handleBlur)
  },

  _params() {
    const params = {}
    for (const attr of this.el.attributes) {
      if (attr.name.startsWith("phx-value-")) {
        params[attr.name.slice(10)] = attr.value
      }
    }
    return params
  }
}

export default CellInput
