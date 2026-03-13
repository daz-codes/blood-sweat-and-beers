class ProgramsController < ApplicationController
  before_action :require_authentication
  before_action :set_program, only: [ :show, :destroy ]

  def new
    @program    = Program.new(weeks_count: 4, sessions_per_week: 3, duration_mins: 45, difficulty: "intermediate")
    @activities = recent_activities_for_user
  end

  def create
    @program = Current.user.programs.build(program_params)
    activity_name = params.dig(:program, :activity).presence || params[:custom_activity].presence

    if activity_name.blank?
      @program.errors.add(:activity, "must be selected, or type a custom activity above")
      @activities = recent_activities_for_user
      render :new, status: :unprocessable_entity and return
    end

    activity = Activity.find_or_create_by!(name: activity_name)
    @program.activity = activity
    @program.name = "#{@program.weeks_count}-Week #{activity.name.titleize} Program"

    if @program.save
      session_notes = Array(params[:session_notes]).first(@program.sessions_per_week)
      ProgramBuilder.build_placeholders(@program, session_notes, custom_activity: params[:custom_activity].presence)
      BuildProgramJob.perform_later(@program.id)
      redirect_to program_path(@program), notice: "Building your #{@program.weeks_count}-week program — workouts will appear as they're generated."
    else
      @activities = recent_activities_for_user
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
    params.require(:program).permit(:weeks_count, :sessions_per_week, :duration_mins, :difficulty)
  end

  def recent_activities_for_user
    Activity.where(id:
      Current.user.workouts.where.not(activity_id: nil)
                           .order(created_at: :desc)
                           .select(:activity_id)
    ).distinct.limit(10)
  end
end
