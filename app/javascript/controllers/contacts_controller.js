import { Controller } from "@hotwired/stimulus"

// Wraps the browser Contact Picker API.
// Lets users find BSB friends from their device contacts, or invite those who aren't members yet.
export default class extends Controller {
  static targets = ["button", "status"]

  get supported() {
    return "contacts" in navigator && "ContactsManager" in window
  }

  connect() {
    if (!this.supported) {
      this.buttonTarget.textContent = "Contact search not supported on this browser"
      this.buttonTarget.disabled = true
      this.buttonTarget.classList.add("opacity-40", "cursor-not-allowed")
    }
  }

  async pick() {
    if (!this.supported) return

    this.buttonTarget.disabled = true
    this.statusTarget.textContent = "Opening contacts…"

    try {
      const contacts = await navigator.contacts.select(["email", "name"], { multiple: true })

      if (!contacts.length) {
        this.statusTarget.textContent = ""
        this.buttonTarget.disabled = false
        return
      }

      const emails = contacts.flatMap(c => c.email || []).filter(Boolean)

      if (!emails.length) {
        this.statusTarget.textContent = "No email addresses found in selected contacts."
        this.buttonTarget.disabled = false
        return
      }

      this.statusTarget.textContent = `Searching ${emails.length} contact${emails.length === 1 ? "" : "s"}…`

      const csrfToken = document.querySelector('meta[name="csrf-token"]').content
      const body = new FormData()
      emails.forEach(e => body.append("emails[]", e))

      const response = await fetch(this.element.dataset.searchUrl, {
        method: "POST",
        headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": csrfToken },
        body
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
        this.statusTarget.textContent = ""
      } else {
        this.statusTarget.textContent = "Something went wrong. Please try again."
      }
    } catch (err) {
      // User cancelled or permission denied — silently reset
      this.statusTarget.textContent = ""
    }

    this.buttonTarget.disabled = false
  }
}
