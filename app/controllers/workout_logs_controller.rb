class WorkoutLogsController < ApplicationController
  before_action :require_authentication

  PAGE_SIZE = 10

  def index
    @page   = [ params[:page].to_i, 1 ].max
    offset  = (@page - 1) * PAGE_SIZE

    logs = Current.user.workout_logs
                   .includes(:tags, photo_attachment: :blob, workout: [ :tags, :workout_likes ])
                   .recent

    results           = logs.offset(offset).limit(PAGE_SIZE + 1).to_a
    @has_more         = results.size > PAGE_SIZE
    @workout_logs     = results.first(PAGE_SIZE)
    @next_page        = @page + 1
    workout_ids       = @workout_logs.map(&:workout_id)
    @liked_workout_ids = WorkoutLike.where(user: Current.user, workout_id: workout_ids).pluck(:workout_id).to_set
  end

  def create
    @workout = Workout.find(params[:workout_id])

    @workout_log = @workout.workout_logs.build(
      user:         Current.user,
      completed_at: Time.current,
      sweat_rating: params[:workout_log][:sweat_rating].to_i,
      notes:        params[:workout_log][:notes].presence,
      location:     params[:workout_log][:location].presence,
      visibility:   params[:workout_log][:private] == "1" ? "private" : "public"
    )

    if @workout_log.save
      @workout_log.photo.attach(params[:workout_log][:photo]) if params[:workout_log][:photo].present?
      save_workout_log_tags(@workout_log, params[:tag_names])
      save_exercise_logs(@workout_log, @workout, params[:step_times] || {})
      redirect_to root_path
    else
      @workout = @workout_log.workout
      render "workouts/log", status: :unprocessable_entity
    end
  end

  def show
    @workout_log = Current.user.workout_logs.find(params[:id])
    @workout     = @workout_log.workout
    @exercise_logs = @workout_log.exercise_logs.order(:step_order).index_by(&:step_order)
  end

  def calendar
    @year  = params[:year].to_i.positive?  ? params[:year].to_i  : Date.current.year
    @month = params[:month].to_i.positive? ? params[:month].to_i : Date.current.month
    @first = Date.new(@year, @month, 1)
    @counts = Current.user.workout_logs
                          .where(completed_at: @first.beginning_of_month..@first.end_of_month)
                          .group("DATE(completed_at)")
                          .count
  end

  def calendar_day
    @date = Date.parse(params[:date])
    @day_logs = Current.user.workout_logs
                            .where(completed_at: @date.all_day)
                            .includes(workout: :tags)
                            .order(:completed_at)
    render layout: false
  rescue ArgumentError
    head :bad_request
  end

  private

  def save_workout_log_tags(workout_log, tag_names_str)
    return if tag_names_str.blank?
    tags = tag_names_str.to_s.split(",").map(&:strip).reject(&:blank?).map do |name|
      Tag.find_or_create_by!(slug: name.parameterize) { |t| t.name = name }
    end
    workout_log.tags = tags
  end

  def save_exercise_logs(workout_log, workout, step_times)
    if workout.structure.is_a?(Hash)
      save_exercise_logs_from_sections(workout_log, workout.structure)
    else
      save_exercise_logs_legacy(workout_log, workout.structure, step_times)
    end
  end

  def save_exercise_logs_from_sections(workout_log, structure)
    Array(structure["sections"]).each_with_index do |section, si|
      Array(section["exercises"]).each_with_index do |ex, ei|
        name = ex["name"].to_s.strip
        next if name.blank?

        set = { "name" => name, "completed" => true }
        set["reps"]       = ex["reps"].to_i      if ex["reps"].to_i > 0
        set["weight_kg"]  = ex["weight_kg"].to_f if ex["weight_kg"].to_f > 0
        set["distance_m"] = ex["distance_m"].to_i if ex["distance_m"].to_i > 0
        set["duration_s"] = ex["duration_s"].to_i if ex["duration_s"].to_i > 0

        rounds = section["rounds"].to_i
        sets   = rounds > 1 ? Array.new(rounds) { set.dup } : [ set ]

        workout_log.exercise_logs.create!(
          exercise_id: nil,
          step_order:  si * 100 + ei,
          sets_data:   sets
        )
      end
    end
  end

  def save_exercise_logs_legacy(workout_log, structure, step_times)
    structure.each do |step|
      order    = step["order"].to_i
      raw_time = step_times[order.to_s].presence

      next unless raw_time

      time_s = parse_time(raw_time)
      next unless time_s

      set_data = { "time_s" => time_s }
      set_data["distance_m"] = step["distance_m"] if step["distance_m"]
      set_data["reps"]       = step["reps"]        if step["reps"]
      set_data["weight_kg"]  = step["weight_kg"]   if step["weight_kg"]

      workout_log.exercise_logs.create!(
        exercise_id: step["exercise_id"],
        step_order:  order,
        sets_data:   [ set_data ]
      )
    end
  end

  # Accepts "5:30", "5m30s", "330" (raw seconds), "5:30.4"
  def parse_time(str)
    str = str.to_s.strip
    if str.match?(/\A\d+:\d{2}\z/)
      parts = str.split(":")
      parts[0].to_i * 60 + parts[1].to_i
    elsif str.match?(/\A\d+\z/)
      str.to_i
    end
  end
end
