class ProgramsController < ApplicationController
  before_action :require_authentication
  before_action :set_program, only: [ :show, :destroy ]

  def new
    @program   = Program.new(weeks_count: 4, sessions_per_week: 3, duration_mins: 45, difficulty: "intermediate")
    @main_tags = Tag.main_focus.order(:name)
  end

  def create
    @program = Current.user.programs.build(program_params)
    @program.name = auto_name(@program)

    if @program.save
      session_notes = Array(params[:session_notes]).first(@program.sessions_per_week)
      ProgramBuilder.build_placeholders(@program, session_notes)
      BuildProgramJob.perform_later(@program.id)
      redirect_to program_path(@program), notice: "Building your #{@program.weeks_count}-week program — workouts will appear as they're generated."
    else
      @main_tags = Tag.main_focus.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @grid = @program.grid
  end

  def destroy
    @program.destroy!
    redirect_to library_path, notice: "Program deleted."
  end

  private

  def set_program
    @program = Current.user.programs.find(params[:id])
  end

  def program_params
    params.require(:program).permit(:tag_id, :weeks_count, :sessions_per_week, :duration_mins, :difficulty)
  end

  def auto_name(program)
    tag_name = Tag.find_by(id: program.tag_id)&.name || "Custom"
    "#{program.weeks_count}-Week #{tag_name} Program"
  end
end
