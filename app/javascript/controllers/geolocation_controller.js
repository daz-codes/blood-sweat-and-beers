import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button", "status"]

  detect() {
    if (!navigator.geolocation) {
      this.#setStatus("Geolocation not supported by your browser")
      return
    }

    this.buttonTarget.disabled = true
    this.#setStatus("Detecting…")

    navigator.geolocation.getCurrentPosition(
      (position) => this.#reverseGeocode(position.coords),
      (err) => {
        const msg = err.code === 1 ? "Location access denied" : "Could not get your location"
        this.#setStatus(msg)
        this.buttonTarget.disabled = false
      },
      { timeout: 10000, maximumAge: 60000 }
    )
  }

  async #reverseGeocode({ latitude, longitude }) {
    try {
      const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&accept-language=en`
      const response = await fetch(url)
      const data = await response.json()
      const a = data.address || {}

      // Build a human-readable location: prefer a named venue, then suburb/district, then city
      const venue   = a.leisure || a.amenity || a.building || a.shop
      const area    = a.suburb || a.neighbourhood || a.quarter || a.village || a.town
      const city    = a.city || a.municipality || a.county

      const parts = [venue, area || city].filter(Boolean)
      this.inputTarget.value = parts.join(", ") || [area, city].filter(Boolean).join(", ")
      this.#setStatus("")
    } catch {
      this.#setStatus("Could not look up location name")
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  #setStatus(text) {
    this.statusTarget.textContent = text
  }
}
