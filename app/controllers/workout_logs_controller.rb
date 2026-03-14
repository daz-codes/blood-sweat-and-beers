class WorkoutLogsController < ApplicationController
  before_action :require_authentication
  rate_limit to: 10, within: 3.minutes, only: :create

  PAGE_SIZE = 10

  def index
    @page   = [ params[:page].to_i, 1 ].max
    offset  = (@page - 1) * PAGE_SIZE

    logs = Current.user.workout_logs
                   .with_feed_includes
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
      @workout_log.create_exercise_logs_from_structure(@workout.structure, params[:step_times] || {})
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
                            .includes(workout: [ :tags, :activity ])
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
end
