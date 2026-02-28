import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drop"]

  highlight(event) {
    const value = parseInt(event.currentTarget.dataset.value)
    this.dropTargets.forEach((drop, i) => {
      drop.classList.toggle("opacity-100", i < value)
      drop.classList.toggle("opacity-25", i >= value)
    })
  }

  reset() {
    const checked = this.element.querySelector("input[type=radio]:checked")
    const value = checked ? parseInt(checked.value) : 0
    this.dropTargets.forEach((drop, i) => {
      drop.classList.toggle("opacity-100", i < value)
      drop.classList.toggle("opacity-25", i >= value)
    })
  }
}
