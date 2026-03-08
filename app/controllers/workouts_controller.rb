class WorkoutsController < ApplicationController
  before_action :require_authentication
  before_action :set_owned_workout, only: [ :edit, :update, :clone ]

  # GET /library
  def index
    @previews  = Current.user.workouts.where(status: "preview").includes(:tags).order(created_at: :desc)
    @workouts  = Current.user.workouts
                       .where.not(status: "preview")
                       .includes(:tags)
                       .order(created_at: :desc)
    if params[:tag_id].present?
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
    @workout.structure = parse_structure(params[:sections])

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
      workout_type:  @workout.workout_type,
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

    if source.user == Current.user
      # User's own generated preview — activate it in place
      source.update!(status: "active") if source.status == "preview"
      redirect_to library_path, notice: "\"#{source.name}\" saved to your library."
      return
    end

    # Another user's workout — copy it if not already saved
    if Current.user.workouts.exists?(source_workout: source)
      redirect_to library_path, notice: "\"#{source.name}\" is already in your library."
      return
    end

    copy = Current.user.workouts.create!(
      name:           source.name,
      workout_type:   source.workout_type,
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

    old_tags      = old.tags
    main_tag      = old_tags.find(&:main?)
    group_tag     = old_tags.find(&:group_code?)
    minor_tag_ids = old_tags.select(&:minor?).map(&:id)

    fresh = WorkoutLLMGenerator.call(
      user:          Current.user,
      main_tag_id:   main_tag&.id,
      minor_tag_ids: minor_tag_ids,
      group_code_id: group_tag&.id,
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

  # GET /workouts/:id/log
  def log
    @workout = Workout.find(params[:id])
  end

  # GET /workouts/:id  (preview)
  def show
    @workout    = Workout.find(params[:id])
    @liked      = @workout.workout_likes.exists?(user: Current.user)
    @like_count = @workout.workout_likes.count
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
    @workout.structure    = parse_structure(params[:sections])
    @workout.workout_type = "custom"
    @workout.status       = "active"

    if @workout.save
      save_workout_tags(@workout)
      redirect_to log_workout_path(@workout), notice: "Workout built — time to log it!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def create_with_llm
    if params[:new_main_tag_name].present?
      custom_main = Tag.find_or_create_by!(slug: params[:new_main_tag_name].strip.parameterize) { |t| t.name = params[:new_main_tag_name].strip; t.tag_type = "main" }
      main_tag_id = custom_main.id.to_s
    else
      main_tag_id = params[:main_tag_id].presence
    end
    minor_tag_ids = Array(params[:minor_tag_ids]).reject(&:blank?)

    params[:new_tag_name].to_s.split(",").map(&:strip).reject(&:blank?).each do |name|
      tag = Tag.find_or_create_by!(slug: name.parameterize) { |t| t.name = name; t.tag_type = "minor" }
      minor_tag_ids << tag.id.to_s
    end

    group_code_id = if params[:group_code].present?
      tag = Tag.find_or_create_by!(slug: params[:group_code].strip.parameterize) { |t| t.name = params[:group_code].strip; t.tag_type = "group_code" }
      tag.update!(tag_type: "group_code") unless tag.group_code?
      tag.id
    end

    @workout = WorkoutLLMGenerator.call(
      user:          Current.user,
      main_tag_id:   main_tag_id,
      minor_tag_ids: minor_tag_ids,
      group_code_id: group_code_id,
      duration_mins: params[:duration_mins],
      difficulty:    params[:difficulty],
      session_notes: params[:new_tag_name].presence
    )

    redirect_to workout_path(@workout)
  rescue WorkoutLLMGenerator::WorkoutGenerationError => e
    Rails.logger.warn "LLM generation failed (#{e.message}) — attempting fallback workout"
    fallback = find_fallback_workout(main_tag_id, params[:difficulty])
    if fallback
      redirect_to workout_path(fallback), alert: "#{e.message} Here's a popular workout to get you moving — try generating again when the AI is back."
    else
      redirect_to root_path, alert: "#{e.message} Please try again in a moment."
    end
  rescue => e
    Rails.logger.error "Workout generation failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to root_path, alert: "Something went wrong generating your workout. Please try again."
  end

  # When the LLM is unavailable, find a popular existing workout with the same tag
  # to show the user instead of an error page. Tries tag match first, falls back to any workout.
  def find_fallback_workout(main_tag_id, difficulty)
    scope = Workout.where(status: "active").where.not(structure: nil)

    if main_tag_id.present?
      tag_match = scope.joins(:taggings)
                       .where(taggings: { tag_id: main_tag_id, taggable_type: "Workout" })
                       .where(difficulty: difficulty.presence || "intermediate")
                       .order("RANDOM()")
                       .first
      return tag_match if tag_match

      # Relax difficulty constraint
      tag_match = scope.joins(:taggings)
                       .where(taggings: { tag_id: main_tag_id, taggable_type: "Workout" })
                       .order("RANDOM()")
                       .first
      return tag_match if tag_match
    end

    # Last resort — any active workout
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

  # Converts nested sections[id][exercises][id] params into the workout JSON structure.
  def parse_structure(sections_param)
    return { "sections" => [] } unless sections_param.present?

    sections = sections_param.to_unsafe_h
                             .sort_by { |k, _| k.to_i }
                             .map { |_, s| build_section(s) }
                             .reject { |s| s["name"].blank? }

    { "sections" => sections }
  end

  def build_section(s)
    section = {
      "name"   => s[:name].to_s.strip,
      "format" => Workout.valid_formats.include?(s[:format]) ? s[:format] : "straight"
    }
    section["rounds"]        = s[:rounds].to_i        if s[:rounds].present?
    section["duration_mins"] = s[:duration_mins].to_i if s[:duration_mins].present?
    section["rest_secs"]     = s[:rest_secs].to_i     if s[:rest_secs].present?
    section["notes"]         = s[:notes].to_s.strip   if s[:notes].present?

    if %w[ladder mountain].include?(section["format"])
      section["varies"] = s[:varies].to_s if s[:varies].present?
      %w[start end step].each do |key|
        next unless s[key.to_sym].present?
        val = s[key.to_sym].to_f
        section[key] = val == val.to_i ? val.to_i : val
      end
      if section["format"] == "mountain" && s[:peak].present?
        val = s[:peak].to_f
        section["peak"] = val == val.to_i ? val.to_i : val
      end
      section["rest_between_rungs"] = s[:rest_between_rungs].to_i if s[:rest_between_rungs].present?
    end

    if s[:exercises].present?
      section["exercises"] = s[:exercises].sort_by { |k, _| k.to_i }
                                          .map { |_, e| build_exercise(e) }
                                          .reject { |e| e["name"].blank? }
    end

    section
  end

  def build_exercise(e)
    ex = { "name" => e[:name].to_s.strip }
    ex["notes"]      = e[:notes].to_s.strip if e[:notes].present?
    ex["reps"]       = e[:reps].to_i        if e[:reps].present?
    ex["calories"]   = e[:calories].to_i    if e[:calories].present?
    ex["distance_m"] = e[:distance_m].to_i  if e[:distance_m].present?
    if e[:duration_m].present? || e[:duration_s_part].present?
      total_s = e[:duration_m].to_i * 60 + e[:duration_s_part].to_i
      ex["duration_s"] = total_s if total_s > 0
    end
    ex["weight_kg"]  = e[:weight_kg].to_f   if e[:weight_kg].present?
    ex
  end
end
