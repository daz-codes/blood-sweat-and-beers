class NotificationsController < ApplicationController
  before_action :require_authentication

  def index
    @notifications = Current.user.notifications
                                  .includes(:actor, :notifiable)
                                  .recent
                                  .limit(50)
    Current.user.notifications.unread.update_all(read_at: Time.current)
  end
end
