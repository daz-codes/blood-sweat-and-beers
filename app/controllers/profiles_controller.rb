class ProfilesController < ApplicationController
  before_action :require_authentication

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    if @user.update(profile_params)
      redirect_to edit_profile_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(:username, :display_name)
  end
end
