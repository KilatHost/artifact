import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "document", "html", "file", "documentInput", "htmlInput", "fileInput", "status"]

  connect() {
    this.changeKind()
  }

  changeKind() {
    const kind = this.kindTarget.value
    this.documentTarget.hidden = kind !== "document"
    this.htmlTarget.hidden = kind !== "html"
    this.fileTarget.hidden = kind !== "file"
    this.documentInputTarget.disabled = kind !== "document"
    this.htmlInputTarget.disabled = kind !== "html"
    this.fileInputTarget.disabled = kind !== "file"
  }

  rejectAttachment(event) {
    event.preventDefault()
    this.statusTarget.textContent = "Embedded attachments are disabled. Use a file artifact instead."
  }
}
