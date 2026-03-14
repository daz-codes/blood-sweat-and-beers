class WorkoutsController < ApplicationController
  before_action :require_authentication
  before_action :set_owned_workout, only: [ :edit, :update, :clone ]
  rate_limit to: 10, within: 3.minutes, only: :create

  # GET /library
  def index
    @programs  = Current.user.programs.order(created_at: :desc)
    @workouts  = Current.user.workouts
                       .includes(:tags, :activity)
                       .order(created_at: :desc)
    if params[:activity].present?
      @activity_filter = params[:activity]
      @workouts = @workouts.joins(:activity).where(activities: { name: params[:activity] })
    elsif params[:tag_id].present?
      @tag = Tag.find_by(id: params[:tag_id])
      @workouts = @workouts.joins(:tags).where(tags: { id: params[:tag_id] }) if @tag
    end
  end

  # GET /workouts/new  — manual builder
  def new
    @workout = Workout.new(difficulty: "intermediate", duration_mins: 60)
  end

  # POST /workouts
  def create
    if params[:source] == "manual"
      create_manual
    else
      create_with_llm
    end
  end

  # GET /workouts/:id/edit
  def edit
  end

  # PATCH /workouts/:id
  def update
    @workout.assign_attributes(manual_workout_params)
    @workout.structure = Workout.structure_from_params(params[:sections])

    if @workout.save
      save_workout_tags(@workout)
      redirect_to workout_path(@workout), notice: "Workout updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /workouts/:id/clone
  def clone
    copy = Current.user.workouts.create!(
      name:          "#{@workout.name} (copy)",
      activity_id:   @workout.activity_id,
      session_notes: @workout.session_notes,
      difficulty:    @workout.difficulty,
      duration_mins: @workout.duration_mins,
      status:        "active",
      structure:     @workout.structure,
      source_workout: @workout
    )
    copy.tags = @workout.tags
    redirect_to edit_workout_path(copy), notice: "Workout cloned — make it your own."
  end

  # POST /workouts/:id/remix
  def remix
    source = Workout.find(params[:id])
    generated = WorkoutLLMGenerator.call(
      user:           Current.user,
      source_workout: source,
      duration_mins:  params[:duration_mins],
      difficulty:     params[:difficulty]
    )
    redirect_to workout_path(generated)
  rescue WorkoutLLMGenerator::WorkoutGenerationError => e
    redirect_back fallback_location: root_path, alert: e.message
  rescue => e
    Rails.logger.error "Remix failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_back fallback_location: root_path, alert: "Something went wrong generating your workout. Please try again."
  end

  # POST /workouts/:id/save
  def save
    source = Workout.find(params[:id])

    # Another user's workout — copy it if not already saved
    if Current.user.workouts.exists?(source_workout: source)
      redirect_to library_path, notice: "\"#{source.name}\" is already in your library."
      return
    end

    copy = Current.user.workouts.create!(
      name:           source.name,
      activity_id:    source.activity_id,
      session_notes:  source.session_notes,
      difficulty:     source.difficulty,
      duration_mins:  source.duration_mins,
      status:         "active",
      structure:      source.structure,
      source_workout: source
    )
    copy.tags = source.tags
    redirect_to library_path, notice: "\"#{copy.name}\" saved to your library."
  end

  # POST /workouts/:id/swap_exercise
  def swap_exercise
    @workout = Current.user.workouts.find(params[:id])
    section_index  = params[:section_index].to_i
    exercise_index = params[:exercise_index].to_i

    replacement = ExerciseSwapService.call(
      workout:        @workout,
      section_index:  section_index,
      exercise_index: exercise_index,
      reason:         params[:reason].presence
    )

    section = Array(@workout.structure["sections"])[section_index]
    render turbo_stream: turbo_stream.replace(
      "exercise_#{@workout.id}_#{section_index}_#{exercise_index}",
      partial: "shared/exercise_row",
      locals: {
        exercise:       replacement,
        workout:        @workout,
        section:        section,
        section_index:  section_index,
        exercise_index: exercise_index,
        swappable:      true
      }
    )
  rescue ExerciseSwapService::SwapError => e
    Rails.logger.warn "Exercise swap failed: #{e.message}"
    render turbo_stream: turbo_stream.replace(
      "exercise_#{@workout.id}_#{section_index}_#{exercise_index}",
      html: "<div id='exercise_#{@workout.id}_#{section_index}_#{exercise_index}' class='px-3 py-2.5 border-t border-zinc-700/50'><p class='text-red-400 text-xs'>Swap failed — please try again.</p></div>".html_safe
    )
  end

  # POST /workouts/:id/regenerate
  def regenerate
    old = Current.user.workouts.find(params[:id])
    unless old.status == "preview"
      redirect_to workout_path(old) and return
    end

    fresh = WorkoutLLMGenerator.call(
      user:          Current.user,
      activity:      old.activity_name,
      session_notes: old.session_notes,
      duration_mins: old.duration_mins,
      difficulty:    old.difficulty
    )
    old.destroy
    redirect_to workout_path(fresh)
  rescue WorkoutLLMGenerator::WorkoutGenerationError => e
    redirect_to workout_path(old), alert: e.message
  rescue => e
    Rails.logger.error "Regenerate failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to workout_path(old), alert: "Something went wrong. Please try again."
  end

  # GET /workouts/:id/export_pdf
  def export_pdf
    unless Current.user.pro?
      redirect_to workout_path(params[:id]), alert: "PDF export is a Pro feature."
      return
    end
    @workout = Workout.find(params[:id])
    pdf_data = WorkoutPdfGenerator.new(@workout).generate
    filename = "volt-workout-#{@workout.name.parameterize}-#{Date.today}.pdf"
    send_data pdf_data, filename: filename, type: "application/pdf", disposition: "attachment"
  end

  # GET /workouts/:id/log
  def log
    @workout = Workout.find(params[:id])
  end

  # GET /workouts/:id  (preview)
  def show
    @workout    = Workout.find(params[:id])
    @liked      = @workout.workout_likes.exists?(user: Current.user)
    @like_count = @workout.workout_likes.count
    @debug_info = Rails.cache.read("workout_llm_debug_#{@workout.id}")
  end

  # PATCH /workouts/:id/save_template
  def save_template
    @workout = Current.user.workouts.find(params[:id])
    @workout.update!(status: "template")
    redirect_to workout_path(@workout), notice: "Saved as template"
  end

  # DELETE /workouts/:id
  def destroy
    @workout = Current.user.workouts.find(params[:id])
    @workout.destroy!
    redirect_to library_path, notice: "\"#{@workout.name}\" deleted."
  end

  private

  def set_owned_workout
    @workout = Current.user.workouts.find(params[:id])
  end

  def manual_workout_params
    params.permit(:name, :duration_mins, :difficulty)
  end

  def create_manual
    @workout = Current.user.workouts.build(manual_workout_params)
    @workout.structure    = Workout.structure_from_params(params[:sections])
    @workout.status       = "active"

    if @workout.save
      save_workout_tags(@workout)
      redirect_to log_workout_path(@workout), notice: "Workout built — time to log it!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def create_with_llm
    if Current.user.generation_limit_reached?
      redirect_to root_path, alert: "You've used all #{User::FREE_GENERATION_LIMIT} free generations this week. Upgrade to Pro for unlimited workouts."
      return
    end

    activity      = params[:activity].presence || params[:custom_activity].presence
    session_notes = params[:session_notes].presence
    group_tag_name = params[:group_code].presence
    prompt_mode   = params[:prompt_mode] == "examples" ? :examples : :full

    @workout = WorkoutLLMGenerator.call(
      user:          Current.user,
      activity:      activity,
      session_notes: session_notes,
      group_tag_name: group_tag_name,
      duration_mins: params[:duration_mins],
      difficulty:    params[:difficulty],
      prompt_mode:   prompt_mode
    )

    Current.user.generation_uses.create!
    redirect_to workout_path(@workout)
  rescue WorkoutLLMGenerator::WorkoutGenerationError => e
    Rails.logger.warn "LLM generation failed (#{e.message}) — attempting fallback workout"
    fallback = find_fallback_workout(activity, params[:difficulty])
    if fallback
      redirect_to workout_path(fallback), alert: "#{e.message} Here's a popular workout to get you moving — try generating again when the AI is back."
    else
      redirect_to root_path, alert: "#{e.message} Please try again in a moment."
    end
  rescue => e
    Rails.logger.error "Workout generation failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to root_path, alert: "Something went wrong generating your workout. Please try again."
  end

  # When the LLM is unavailable, find a popular existing workout with the same activity
  # to show the user instead of an error page.
  def find_fallback_workout(activity_name, difficulty)
    scope = Workout.where(status: "active").where.not(structure: nil)

    if activity_name.present?
      match = scope.joins(:activity)
                   .where(activities: { name: activity_name }, difficulty: difficulty.presence || "intermediate")
                   .order("RANDOM()")
                   .first
      return match if match

      match = scope.joins(:activity).where(activities: { name: activity_name }).order("RANDOM()").first
      return match if match
    end

    scope.order("RANDOM()").first
  end

  def save_workout_tags(workout)
    tag_ids = Array(params[:tag_ids]).reject(&:blank?)
    params[:new_tag_name].to_s.split(",").map(&:strip).reject(&:blank?).each do |name|
      tag = Tag.find_or_create_by!(slug: name.parameterize) { |t| t.name = name }
      tag_ids << tag.id.to_s
    end
    workout.tag_ids = tag_ids
  end
end
