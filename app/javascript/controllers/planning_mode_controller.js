import { Controller } from "@hotwired/stimulus"

const DISTANCE_SLUGS = /^(run|swim|row|ski|bike|cycl|jog|tri|duat)/

const SLUG_RANGES = [
  { prefix: "swim", min: 0.5, max: 10,   step: 0.25, minLabel: "500 m",  maxLabel: "10 km" },
  { prefix: "run",  min: 1,   max: 42,   step: 1,    minLabel: "1 km",   maxLabel: "42 km" },
  { prefix: "jog",  min: 1,   max: 42,   step: 1,    minLabel: "1 km",   maxLabel: "42 km" },
  { prefix: "row",  min: 0.5, max: 30,   step: 0.5,  minLabel: "500 m",  maxLabel: "30 km" },
  { prefix: "ski",  min: 0.5, max: 30,   step: 0.5,  minLabel: "500 m",  maxLabel: "30 km" },
  { prefix: "bike", min: 5,   max: 100,  step: 5,    minLabel: "5 km",   maxLabel: "100 km" },
  { prefix: "cycl", min: 5,   max: 100,  step: 5,    minLabel: "5 km",   maxLabel: "100 km" },
]
const DEFAULT_RANGE = { min: 0.5, max: 42, step: 0.5, minLabel: "0.5 km", maxLabel: "42 km" }

function rangeForSlug(slug) {
  return SLUG_RANGES.find(r => slug.startsWith(r.prefix)) ?? DEFAULT_RANGE
}

export default class extends Controller {
  static targets = ["timePanel", "distancePanel", "distanceInput", "distanceDisplay",
                    "warning", "modeField", "timeBtn", "distanceBtn",
                    "distanceLabelMin", "distanceLabelMax"]

  connect() {
    this.updateDistanceDisplay()
    this.checkWarning()
  }

  showTime() {
    this.timePanelTarget.hidden = false
    this.distancePanelTarget.hidden = true
    this.modeFieldTarget.value = "time"
    this.timeBtnTarget.dataset.active = "true"
    this.distanceBtnTarget.dataset.active = "false"
    if (this.hasWarningTarget) this.warningTarget.hidden = true
  }

  showDistance() {
    this.timePanelTarget.hidden = true
    this.distancePanelTarget.hidden = false
    this.modeFieldTarget.value = "distance"
    this.timeBtnTarget.dataset.active = "false"
    this.distanceBtnTarget.dataset.active = "true"
    this.checkWarning()
  }

  updateDistanceDisplay() {
    if (!this.hasDistanceInputTarget) return
    const val = parseFloat(this.distanceInputTarget.value)
    this.distanceDisplayTarget.textContent = val % 1 === 0 ? String(val) : val.toFixed(2).replace(/\.?0+$/, "")
  }

  // Called when session type radios change — auto-switch mode, update warning and slider range
  checkWarning() {
    const checked = this.element.querySelector('input[name="main_tag_id"]:checked')
    const slug = checked?.dataset?.slug ?? ""

    // Auto-switch to distance mode when a distance sport (swim, run, row…) is selected
    if (DISTANCE_SLUGS.test(slug) && this.modeFieldTarget.value !== "distance") {
      this.timePanelTarget.hidden = true
      this.distancePanelTarget.hidden = false
      this.modeFieldTarget.value = "distance"
      this.timeBtnTarget.dataset.active = "false"
      this.distanceBtnTarget.dataset.active = "true"
    }

    if (this.hasWarningTarget && this.modeFieldTarget.value === "distance") {
      this.warningTarget.hidden = DISTANCE_SLUGS.test(slug)
    }

    this.updateSliderRange(slug)
  }

  updateSliderRange(slug) {
    if (!this.hasDistanceInputTarget) return
    const range = rangeForSlug(slug)
    const input = this.distanceInputTarget
    const current = parseFloat(input.value)

    input.min  = range.min
    input.max  = range.max
    input.step = range.step

    // Clamp current value to new range and snap to nearest step
    const clamped = Math.min(Math.max(current, range.min), range.max)
    const snapped = Math.round(clamped / range.step) * range.step
    if (Math.abs(snapped - current) > 0.001) {
      input.value = snapped
      this.updateDistanceDisplay()
    }

    if (this.hasDistanceLabelMinTarget) this.distanceLabelMinTarget.textContent = range.minLabel
    if (this.hasDistanceLabelMaxTarget) this.distanceLabelMaxTarget.textContent = range.maxLabel
  }
}
