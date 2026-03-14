module Program::Broadcasting
  extend ActiveSupport::Concern

  private

  def broadcast_slot(pw)
    pw_fresh = pw.reload
    Turbo::StreamsChannel.broadcast_replace_to(
      "program_#{id}", target: pw_fresh.turbo_dom_id,
      partial: "programs/program_workout_slot", locals: { program_workout: pw_fresh }
    )
  end

  def broadcast_program_complete
    Turbo::StreamsChannel.broadcast_replace_to(
      "program_#{id}", target: "program_header_#{id}",
      partial: "programs/program_header", locals: { program: reload }
    )
  end
end
