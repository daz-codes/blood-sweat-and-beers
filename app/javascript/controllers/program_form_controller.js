import { Controller } from "@hotwired/stimulus"

// Keeps session focus fields in sync with the selected sessions-per-week count.
// Also drives the weeks-count slider display.
export default class extends Controller {
  static targets = ["weeksDisplay", "weeksInput", "sessionRow"]

  connect() {
    this.updateSessions()
  }

  updateWeeks() {
    if (this.hasWeeksDisplayTarget && this.hasWeeksInputTarget) {
      this.weeksDisplayTarget.textContent = this.weeksInputTarget.value
    }
  }

  updateSessions() {
    const selected = this.element.querySelector("input[name='program[sessions_per_week]']:checked")
    const count = selected ? parseInt(selected.value) : 3

    this.sessionRowTargets.forEach((row, i) => {
      row.classList.toggle("hidden", i >= count)
      // Clear hidden fields so they don't submit empty strings
      if (i >= count) {
        const input = row.querySelector("input")
        if (input) input.value = ""
      }
    })
  }
}
