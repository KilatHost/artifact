import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "label"]

  async copy() {
    this.idle ??= this.labelTarget.textContent
    const text = this.sourceTarget.textContent.trim()
    try {
      await navigator.clipboard.writeText(text)
      this.labelTarget.textContent = "Copied"
    } catch (_) {
      const range = document.createRange()
      range.selectNodeContents(this.sourceTarget)
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
      this.labelTarget.textContent = "Press ⌘C"
    }
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { this.labelTarget.textContent = this.idle }, 2000)
  }
}
