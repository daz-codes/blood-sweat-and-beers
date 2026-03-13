class WorkoutLikesController < ApplicationController
  before_action :require_authentication

  def toggle
    @workout = Workout.find(params[:id])
    @workout.workout_likes.create!(user: Current.user)
    @liked = true
    @like_count = @workout.workout_likes.count

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @workout }
    end
  end
end
