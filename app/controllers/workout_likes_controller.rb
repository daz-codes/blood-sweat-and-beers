class WorkoutLikesController < ApplicationController
  before_action :require_authentication

  def toggle
    @workout = Workout.find(params[:id])
    existing = @workout.workout_likes.find_by(user: Current.user)

    if existing
      existing.destroy
      @liked = false
    else
      @workout.workout_likes.create!(user: Current.user)
      @liked = true
    end

    @like_count = @workout.workout_likes.count

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @workout }
    end
  end
end
