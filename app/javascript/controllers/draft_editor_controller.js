import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["attachmentStatus", "modeControls", "textSection", "sourceSection", "textButton", "sourceButton", "source", "sourceHint", "markdownLine", "htmlBlock"]
  static values = { kind: String, preferSource: Boolean }

  connect() {
    if (!this.hasModeControlsTarget) return

    this.formattedSource = this.sourceTarget.value
    this.modeControlsTarget.hidden = false
    this.setMode(!this.preferSourceValue)
  }

  showText() {
    this.setMode(true)
  }

  showSource() {
    this.setMode(false)
  }

  setMode(text) {
    this.textSectionTarget.hidden = !text
    this.sourceSectionTarget.hidden = text
    this.textButtonTarget.setAttribute("aria-pressed", text)
    this.sourceButtonTarget.setAttribute("aria-pressed", !text)
    if (this.kindValue === "html") {
      this.sourceTarget.disabled = text
      this.htmlBlockTargets.forEach(field => { field.disabled = !text })
    }
  }

  syncMarkdown({ currentTarget: field }) {
    const lines = this.formattedSource.split("\n")
    lines[Number(field.dataset.index)] = field.dataset.prefix + field.value
    this.formattedSource = lines.join("\n")
    this.sourceTarget.value = this.formattedSource
  }

  sourceChanged() {
    if (!this.hasSourceHintTarget) return

    const changed = this.sourceTarget.value !== this.formattedSource
    this.textButtonTarget.disabled = changed
    this.sourceHintTarget.hidden = !changed
  }

  rejectAttachment(event) {
    event.preventDefault()
    this.attachmentStatusTarget.textContent = "Files can't go inside a document. Make a File artifact instead."
  }
}
