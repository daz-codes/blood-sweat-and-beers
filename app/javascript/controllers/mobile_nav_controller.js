import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "burger", "close"]

  toggle() {
    const open = this.menuTarget.classList.toggle("hidden")
    this.burgerTarget.classList.toggle("hidden", !open)
    this.closeTarget.classList.toggle("hidden", open)
  }

  // Close if user navigates (Turbo visit)
  disconnect() {
    this.menuTarget.classList.add("hidden")
  }
}
