import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "document", "markdown", "html", "file", "documentInput", "markdownInput", "htmlInput", "fileInput", "status"]

  connect() {
    this.changeKind()
  }

  changeKind() {
    const kind = this.kindTarget.value
    const source = ["html", "doc", "sheet", "slides"].includes(kind)
    this.documentTarget.hidden = kind !== "document"
    this.markdownTarget.hidden = kind !== "markdown"
    this.htmlTarget.hidden = !source
    this.fileTarget.hidden = kind !== "file"
    this.documentInputTarget.disabled = kind !== "document"
    this.markdownInputTarget.disabled = kind !== "markdown"
    this.htmlInputTarget.disabled = !source
    this.fileInputTarget.disabled = kind !== "file"
  }

  rejectAttachment(event) {
    event.preventDefault()
    this.statusTarget.textContent = "Files can't go inside a document. Make a File artifact instead."
  }
}
