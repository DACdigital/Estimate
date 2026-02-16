const AiEnhance = {
  mounted() {
    this.el.addEventListener("click", () => {
      const form = this.el.closest("form")
      if (!form) return

      const textareaName = this.el.dataset.textareaName
      const nameInputName = this.el.dataset.nameInput
      const textarea = form.querySelector(`[name="${textareaName}"]`)
      const nameInput = form.querySelector(`[name="${nameInputName}"]`)

      const description = textarea ? textarea.value.trim() : ""
      const name = nameInput ? nameInput.value.trim() : ""

      if (!description) return

      this.pushEvent("ai_enhance_description", {
        description,
        name,
        target: textareaName,
      })
    })

    this.handleEvent("ai_set_description", ({ text, target }) => {
      const form = this.el.closest("form")
      if (!form) return

      const textarea = form.querySelector(`[name="${target}"]`)
      if (!textarea) return

      textarea.value = text
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    })
  },
}

export default AiEnhance
