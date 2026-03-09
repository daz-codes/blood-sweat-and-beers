class SubscriptionsController < ApplicationController
  before_action :require_authentication

  def upgrade
    Current.user.update!(plan: "pro")
    redirect_to profile_path, notice: "You're now on Pro!"
  end

  def downgrade
    Current.user.update!(plan: "free")
    redirect_to profile_path, notice: "Downgraded to Free plan."
  end
end
