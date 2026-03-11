class BuildProgramJob < ApplicationJob
  queue_as :default

  def perform(program_id)
    program = Program.find_by(id: program_id)
    return unless program

    program.update!(status: "building")

    week1_workouts = {}

    # Phase 1: generate Week 1 sessions
    program.program_workouts
           .where(week_number: 1)
           .order(:session_number)
           .each do |pw|
      generate_slot(program, pw, source: nil)
      week1_workouts[pw.session_number] = pw.reload.workout
    end

    # Phase 2: remix for weeks 2-N
    if program.weeks_count > 1
      program.program_workouts
             .where.not(week_number: 1)
             .order(:week_number, :session_number)
             .each do |pw|
        source = week1_workouts[pw.session_number]
        generate_slot(program, pw, source: source)
      end
    end

    program.update!(status: "complete")
    broadcast_program_complete(program)
  rescue => e
    Rails.logger.error "BuildProgramJob failed for program #{program_id}: #{e.message}"
    program&.update(status: "failed")
  end

  private

  def generate_slot(program, pw, source:)
    pw.update!(status: "generating")
    broadcast_slot(pw)

    workout = if source
      WorkoutLLMGenerator.call(
        user:           program.user,
        source_workout: source,
        duration_mins:  program.duration_mins,
        difficulty:     program.difficulty
      )
    else
      WorkoutLLMGenerator.call(
        user:          program.user,
        main_tag_id:   program.tag_id,
        duration_mins: program.duration_mins,
        difficulty:    program.difficulty,
        session_notes: pw.session_notes
      )
    end

    pw.update!(workout: workout, status: "complete")
    broadcast_slot(pw)
  rescue => e
    Rails.logger.error "Program #{program.id} slot #{pw.id} failed: #{e.message}"
    pw.update!(status: "failed")
    broadcast_slot(pw)
  end

  def broadcast_slot(pw)
    pw_fresh = pw.reload
    Turbo::StreamsChannel.broadcast_replace_to(
      "program_#{pw_fresh.program_id}",
      target:  pw_fresh.turbo_dom_id,
      partial: "programs/program_workout_slot",
      locals:  { program_workout: pw_fresh }
    )
  end

  def broadcast_program_complete(program)
    Turbo::StreamsChannel.broadcast_replace_to(
      "program_#{program.id}",
      target:  "program_header_#{program.id}",
      partial: "programs/program_header",
      locals:  { program: program.reload }
    )
  end
end
