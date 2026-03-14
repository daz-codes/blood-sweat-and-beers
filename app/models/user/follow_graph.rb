module User::FollowGraph
  extend ActiveSupport::Concern

  included do
    has_many :follows_as_follower,  class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
    has_many :follows_as_following, class_name: "Follow", foreign_key: :following_id, dependent: :destroy
  end

  def accepted_following_ids
    follows_as_follower.accepted.pluck(:following_id)
  end

  def pending_follow_request_count
    follows_as_following.pending.count
  end

  def follow_state_for(other_user)
    return :self if id == other_user.id
    follow = follows_as_follower.find_by(following_id: other_user.id)
    return :none unless follow
    follow.status.to_sym
  end
end
