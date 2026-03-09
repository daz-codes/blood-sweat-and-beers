class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :actor,     class_name: "User"
  belongs_to :notifiable, polymorphic: true

  scope :unread,  -> { where(read_at: nil) }
  scope :recent,  -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def message
    name = actor.display
    case action
    when "follow_request"  then "#{name} wants to follow you"
    when "follow_accepted" then "#{name} accepted your follow request"
    when "comment"         then "#{name} commented on your workout"
    when "like"            then "#{name} liked your workout"
    end
  end
end
