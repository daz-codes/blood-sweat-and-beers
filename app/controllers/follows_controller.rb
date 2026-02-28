class FollowsController < ApplicationController
  before_action :require_authentication
  before_action :set_follow, only: [ :destroy, :accept ]

  # GET /follows — inbound pending requests inbox
  def index
    @pending_follows = Current.user.follows_as_following.pending
                              .includes(:follower)
                              .order(requested_at: :desc)
  end

  # GET /follows/pending_count — for nav badge Turbo Frame
  def pending_count
    @count = Current.user.pending_follow_request_count
    render layout: false
  end

  # POST /follows
  def create
    target = User.find(params[:following_id])

    if target == Current.user
      head :unprocessable_entity and return
    end

    follow = Current.user.follows_as_follower.find_or_initialize_by(following: target)

    if follow.new_record?
      follow.save!
    end

    @follow_state = follow.status.to_sym
    @target_user  = target

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: user_path(target) }
    end
  end

  # DELETE /follows/:id — unfollow or cancel pending
  def destroy
    target = @follow.following == Current.user ? @follow.follower : @follow.following
    @follow.destroy!
    @follow_state = :none
    @target_user  = target

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: user_path(target) }
    end
  end

  # PATCH /follows/:id/accept — accept an inbound request
  def accept
    # Only the followee can accept
    unless @follow.following == Current.user
      head :forbidden and return
    end

    @follow.accept!
    @requester = @follow.follower

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to follows_path }
    end
  end

  private

  def set_follow
    @follow = Follow.find(params[:id])
    # Must be one of the parties involved
    unless @follow.follower == Current.user || @follow.following == Current.user
      head :forbidden
    end
  end
end
