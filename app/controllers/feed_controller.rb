class FeedController < ApplicationController
  before_action :require_authentication

  PAGE_SIZE = 10

  def index
    @page = [ params[:page].to_i, 1 ].max
    offset = (@page - 1) * PAGE_SIZE

    visible_user_ids = [ Current.user.id ] + Current.user.accepted_following_ids

    logs = WorkoutLog.where(user_id: visible_user_ids)
                     .includes(:user, :tags, photo_attachment: :blob, workout: [ :tags, :workout_likes ])
                     .recent

    results = logs.offset(offset).limit(PAGE_SIZE + 1).to_a

    @has_more      = results.size > PAGE_SIZE
    @workout_logs  = results.first(PAGE_SIZE)
    @next_page     = @page + 1
    workout_ids    = @workout_logs.map(&:workout_id)
    @liked_workout_ids = WorkoutLike.where(user: Current.user, workout_id: workout_ids).pluck(:workout_id).to_set
  end
end
