import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  open() {
    this.modalTarget.showModal()
  }

  close() {
    this.modalTarget.close()
  }

  // Close when clicking the backdrop (the dialog element itself, not its content)
  backdropClick(event) {
    if (event.target === this.modalTarget) this.close()
  }
}
