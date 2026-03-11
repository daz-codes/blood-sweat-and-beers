class ProgramBuilder
  SESSION_FOCUSES = [
    "strength and power focus — heavy compound movements, lower rep ranges",
    "cardio engine and endurance focus — sustained effort, machine work, conditioning",
    "mixed modal and full body — variety of formats, balanced across all qualities"
  ].freeze

  def self.build_placeholders(program, session_notes = [])
    rows = []
    (1..program.weeks_count).each do |week|
      (1..program.sessions_per_week).each do |session|
        notes = session_notes[session - 1].presence
        # For week 1 with no user notes, assign a balanced focus
        if week == 1 && notes.nil?
          notes = SESSION_FOCUSES[(session - 1) % SESSION_FOCUSES.size]
        end
        rows << {
          program_id:     program.id,
          week_number:    week,
          session_number: session,
          session_notes:  notes,
          status:         "pending",
          created_at:     Time.current,
          updated_at:     Time.current
        }
      end
    end
    ProgramWorkout.insert_all!(rows)
  end
end
