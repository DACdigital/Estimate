// SearchFocus hook: handles "/" keyboard shortcut and arrow key navigation
const SearchFocus = {
  mounted() {
    this.handleKeydown = (e) => {
      // Focus on "/" key (not in input/textarea)
      if (e.key === "/" && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
        e.preventDefault()
        const input = this.el.querySelector("input")
        if (input) {
          input.focus()
          input.select()
        }
      }
    }

    // Handle arrow keys and enter/escape within the search input
    this.handleInputKeydown = (e) => {
      if (["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(e.key)) {
        e.preventDefault()
        this.pushEventTo(this.el, "navigate_results", { key: e.key })
      }
    }

    document.addEventListener("keydown", this.handleKeydown)

    const input = this.el.querySelector("input")
    if (input) {
      input.addEventListener("keydown", this.handleInputKeydown)
    }
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown)

    const input = this.el.querySelector("input")
    if (input) {
      input.removeEventListener("keydown", this.handleInputKeydown)
    }
  }
}

export default SearchFocus
