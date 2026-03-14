import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pill", "customInput", "submitBtn"]

  customTyped() {
    if (this.customInputTarget.value.trim() !== "") {
      this.pillTargets.forEach(radio => radio.checked = false)
    }
  }

  pillSelected() {
    this.customInputTarget.value = ""
  }

  showSpinner() {
    this.submitBtnTarget.disabled = true
    this.submitBtnTarget.innerHTML =
      '<span class="inline-flex items-center justify-center gap-2">' +
        '<svg class="animate-spin h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">' +
          '<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>' +
          '<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>' +
        '</svg>' +
        'Generating\u2026' +
      '</span>'

    // Close the modal and show a full-page loading overlay
    const dialog = this.element.closest("dialog")
    if (dialog) dialog.close()

    const overlay = document.createElement("div")
    overlay.id = "generating-overlay"
    overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-zinc-900/90"
    overlay.innerHTML =
      '<div class="text-center">' +
        '<svg class="animate-spin h-10 w-10 text-lime-400 mx-auto mb-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">' +
          '<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>' +
          '<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>' +
        '</svg>' +
        '<p class="text-white text-lg font-semibold">Generating your workout\u2026</p>' +
        '<p class="text-gray-400 text-sm mt-1">This usually takes 10\u201320 seconds</p>' +
      '</div>'
    document.body.appendChild(overlay)
  }
}
