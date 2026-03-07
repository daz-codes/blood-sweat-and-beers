import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon", "name", "details"]

  swap() {
    this.iconTarget.classList.add("animate-spin")
    this.nameTarget.textContent = "Looking for an alternative…"
    this.nameTarget.classList.remove("text-white", "font-semibold")
    this.nameTarget.classList.add("text-gray-400", "italic")
    if (this.hasDetailsTarget) {
      this.detailsTarget.classList.add("hidden")
    }
  }
}
