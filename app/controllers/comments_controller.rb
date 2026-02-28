class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_workout_log

  def index
    @comments = @workout_log.comments.includes(:user).chronological
    @comment  = Comment.new
  end

  def create
    @comment = @workout_log.comments.build(body: params[:comment][:body], user: Current.user)

    if @comment.save
      @comments = @workout_log.comments.includes(:user).chronological
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "comment_form_#{@workout_log.id}",
            partial: "comments/form",
            locals: { workout_log: @workout_log, comment: @comment }
          )
        end
        format.html { redirect_back fallback_location: root_path }
      end
    end
  end

  def destroy
    @comment = @workout_log.comments.find(params[:id])

    unless @comment.user == Current.user
      head :forbidden and return
    end

    @comment.destroy!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def set_workout_log
    @workout_log = WorkoutLog.find(params[:workout_log_id])
  end
end
