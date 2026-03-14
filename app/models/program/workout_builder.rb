module Program::WorkoutBuilder
  extend ActiveSupport::Concern

  SESSION_FOCUSES = [
    "strength and power focus — heavy compound movements, lower rep ranges",
    "cardio engine and endurance focus — sustained effort, machine work, conditioning",
    "mixed modal and full body — variety of formats, balanced across all qualities"
  ].freeze

  def create_workout_placeholders(session_notes = [], custom_activity: nil)
    rows = []
    (1..weeks_count).each do |week|
      (1..sessions_per_week).each do |session|
        notes = session_notes[session - 1].presence
        notes = SESSION_FOCUSES[(session - 1) % SESSION_FOCUSES.size] if week == 1 && notes.nil?
        notes = [ custom_activity, notes ].compact.join(" — ").presence if custom_activity
        rows << {
          program_id: id, week_number: week, session_number: session,
          session_notes: notes, status: "pending",
          created_at: Time.current, updated_at: Time.current
        }
      end
    end
    ProgramWorkout.insert_all!(rows)
  end

  def build_later
    BuildProgramJob.perform_later(id)
  end

  def build!
    update!(status: "building")

    week1_workouts = {}
    program_workouts.where(week_number: 1).order(:session_number).each do |pw|
      generate_slot(pw, source: nil)
      week1_workouts[pw.session_number] = pw.reload.workout
    end

    if weeks_count > 1
      program_workouts.where.not(week_number: 1).order(:week_number, :session_number).each do |pw|
        generate_slot(pw, source: week1_workouts[pw.session_number])
      end
    end

    update!(status: "complete")
    broadcast_program_complete
  rescue => e
    Rails.logger.error "Program#build! failed for #{id}: #{e.message}"
    update(status: "failed")
  end

  private

  def generate_slot(pw, source:)
    pw.update!(status: "generating")
    broadcast_slot(pw)

    workout = if source
      WorkoutLLMGenerator.call(user: user, source_workout: source, duration_mins: duration_mins,
                               difficulty: difficulty, session_notes: pw.session_notes)
    else
      WorkoutLLMGenerator.call(user: user, activity: activity&.name, duration_mins: duration_mins,
                               difficulty: difficulty, session_notes: pw.session_notes)
    end

    pw.update!(workout: workout, status: "complete")
    broadcast_slot(pw)
  rescue => e
    Rails.logger.error "Program #{id} slot #{pw.id} failed: #{e.message}"
    pw.update!(status: "failed")
    broadcast_slot(pw)
  end
end
