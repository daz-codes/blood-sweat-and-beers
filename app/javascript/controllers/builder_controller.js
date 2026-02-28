import { Controller } from "@hotwired/stimulus"

// Manages the dynamic workout builder form.
// Sections and exercises are added/removed via template strings.
// Field names use timestamps as indices so Rails params parse in insertion order.
export default class extends Controller {
  static targets = ["sectionsList"]

  addSection() {
    const id = Date.now()
    this.sectionsListTarget.insertAdjacentHTML("beforeend", this.sectionTemplate(id))
  }

  removeSection(event) {
    event.currentTarget.closest("[data-section-id]").remove()
  }

  addExercise(event) {
    const section   = event.currentTarget.closest("[data-section-id]")
    const sectionId = section.dataset.sectionId
    const exId      = Date.now() + Math.floor(Math.random() * 1000)
    section.querySelector("[data-exercises-list]").insertAdjacentHTML("beforeend", this.exerciseTemplate(sectionId, exId))
  }

  removeExercise(event) {
    event.currentTarget.closest("[data-exercise-id]").remove()
  }

  toggleFormat(event) {
    const section = event.currentTarget.closest("[data-section-id]")
    const format  = event.currentTarget.value
    section.querySelectorAll("[data-format-field]").forEach(el => {
      el.style.display = el.dataset.formatField === format ? "" : "none"
    })
  }

  toggleMetric(event) {
    const exercise = event.currentTarget.closest("[data-exercise-id]")
    const type     = event.currentTarget.value
    exercise.querySelectorAll("[data-metric]").forEach(el => {
      el.style.display = el.dataset.metric === type ? "" : "none"
    })
  }

  sectionTemplate(id) {
    return `
      <div data-section-id="${id}" class="border border-gray-700 rounded-2xl p-4">
        <div class="flex items-center gap-2 mb-3">
          <input name="sections[${id}][name]" type="text" placeholder="Section name (e.g. Warm Up, Main Set)" required
            class="flex-1 bg-gray-900 border border-gray-700 rounded-xl px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
          <select name="sections[${id}][format]" data-action="change->builder#toggleFormat"
            class="bg-gray-900 border border-gray-700 rounded-xl px-3 py-2 text-sm text-white focus:outline-none focus:border-orange-500 transition-colors">
            <option value="straight">Straight</option>
            <option value="rounds">Rounds</option>
            <option value="amrap">AMRAP</option>
            <option value="emom">EMOM</option>
            <option value="tabata">Tabata</option>
          </select>
          <button type="button" data-action="builder#removeSection"
            class="text-gray-600 hover:text-red-500 transition-colors flex-shrink-0 p-1" aria-label="Remove section">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>
              <path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/>
            </svg>
          </button>
        </div>
        <div data-format-field="rounds" style="display:none" class="flex items-center gap-2 mb-3">
          <input name="sections[${id}][rounds]" type="number" min="1" placeholder="Number of rounds"
            class="w-40 bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
          <input name="sections[${id}][rest_secs]" type="number" min="0" placeholder="Rest between rounds (secs)"
            class="w-48 bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
        </div>
        <div data-format-field="amrap" style="display:none" class="mb-3">
          <input name="sections[${id}][duration_mins]" type="number" min="1" placeholder="Duration (minutes)"
            class="w-44 bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
        </div>
        <div data-format-field="emom" style="display:none" class="mb-3">
          <div class="flex items-center gap-3">
            <input name="sections[${id}][duration_mins]" type="number" min="1" placeholder="Duration (minutes)"
              class="w-44 bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
            <p class="text-xs text-gray-500">Every Minute On the Minute — list the exercises done each minute.</p>
          </div>
        </div>
        <div data-format-field="tabata" style="display:none" class="mb-3">
          <div class="flex items-center gap-2">
            <span class="text-xs font-bold text-purple-400 bg-purple-500/10 border border-purple-500/25 px-3 py-1.5 rounded-full">8 rounds · 20s on · 30s rest</span>
            <p class="text-xs text-gray-500">Add the exercises performed during each work interval.</p>
          </div>
        </div>
        <div data-exercises-list class="space-y-2 mb-3"></div>
        <button type="button" data-action="builder#addExercise"
          class="text-sm text-orange-500 hover:text-orange-400 transition-colors font-medium">
          + Add Exercise
        </button>
      </div>`
  }

  exerciseTemplate(sectionId, exId) {
    return `
      <div data-exercise-id="${exId}" class="bg-gray-900/60 border border-gray-800 rounded-xl p-3 space-y-2">
        <div class="flex items-start gap-2">
          <div class="flex-1 space-y-2">
            <input name="sections[${sectionId}][exercises][${exId}][name]" type="text" placeholder="Exercise name" required
              class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
            <input name="sections[${sectionId}][exercises][${exId}][notes]" type="text" placeholder="Description or cue (optional)"
              class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
            <div class="flex items-center gap-2 flex-wrap">
              <select data-action="change->builder#toggleMetric"
                class="bg-gray-900 border border-gray-700 rounded-lg px-2 py-1.5 text-xs text-gray-300 focus:outline-none focus:border-orange-500 transition-colors">
                <option value="reps">Reps</option>
                <option value="distance">Distance</option>
                <option value="duration">Time</option>
              </select>
              <div data-metric="reps">
                <input name="sections[${sectionId}][exercises][${exId}][reps]" type="number" min="1" placeholder="Reps"
                  class="w-20 bg-gray-900 border border-gray-700 rounded-lg px-2 py-1.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
              </div>
              <div data-metric="distance" style="display:none">
                <input name="sections[${sectionId}][exercises][${exId}][distance_m]" type="number" min="1" placeholder="Metres"
                  class="w-24 bg-gray-900 border border-gray-700 rounded-lg px-2 py-1.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
              </div>
              <div data-metric="duration" style="display:none" class="flex items-center gap-1">
                <input name="sections[${sectionId}][exercises][${exId}][duration_m]" type="number" min="0" placeholder="Mins"
                  class="w-16 bg-gray-900 border border-gray-700 rounded-lg px-2 py-1.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
                <span class="text-xs text-gray-600">m</span>
                <input name="sections[${sectionId}][exercises][${exId}][duration_s_part]" type="number" min="0" max="59" placeholder="Secs"
                  class="w-16 bg-gray-900 border border-gray-700 rounded-lg px-2 py-1.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
                <span class="text-xs text-gray-600">s</span>
              </div>
              <input name="sections[${sectionId}][exercises][${exId}][weight_kg]" type="number" min="0" step="0.5" placeholder="kg (opt.)"
                class="w-24 bg-gray-900 border border-gray-700 rounded-lg px-2 py-1.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-orange-500 transition-colors">
            </div>
          </div>
          <button type="button" data-action="builder#removeExercise"
            class="text-gray-600 hover:text-red-500 transition-colors flex-shrink-0 mt-1 p-0.5" aria-label="Remove exercise">
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>
      </div>`
  }
}
