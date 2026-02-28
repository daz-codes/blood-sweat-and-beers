class UsersController < ApplicationController
  before_action :require_authentication

  # GET /users?q=
  def index
    if params[:q].present?
      q = "%#{params[:q].gsub('%', '').gsub('_', '\\_')}%"
      @users = User.where("username ILIKE :q OR display_name ILIKE :q", q: q)
                   .where.not(id: Current.user.id)
                   .limit(20)
    else
      @users = []
    end
  end

  # GET /users/:id
  def show
    @profile_user = User.find(params[:id])

    # Redirect to own edit profile if viewing self
    if @profile_user == Current.user
      redirect_to edit_profile_path and return
    end

    @follow_state   = Current.user.follow_state_for(@profile_user)
    @follow         = Current.user.follows_as_follower.find_by(following: @profile_user)
    @workout_count  = @profile_user.workout_logs.count
    @follower_count = @profile_user.follows_as_following.accepted.count
    @following_count = @profile_user.follows_as_follower.accepted.count

    if @follow_state == :accepted
      @recent_logs = @profile_user.workout_logs
                                  .includes(workout: [:tags])
                                  .recent
                                  .limit(10)
    end
  end
end
