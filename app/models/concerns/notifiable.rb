module Notifiable
  extend ActiveSupport::Concern

  class_methods do
    def notifies(action:, recipient:, actor: :user)
      after_create_commit -> { create_notification(action, recipient, actor) }
    end
  end

  private

  def create_notification(action, recipient_method, actor_method)
    recipient = send(recipient_method)
    actor     = send(actor_method)
    return if recipient == actor

    Notification.create!(
      recipient:  recipient,
      actor:      actor,
      notifiable: self,
      action:     action.to_s
    )
  end
end
