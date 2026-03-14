class BuildProgramJob < ApplicationJob
  queue_as :default

  def perform(program_id)
    program = Program.find_by(id: program_id)
    return unless program

    program.build!
  end
end
