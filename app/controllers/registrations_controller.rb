class RegistrationsController < ApplicationController
  allow_unauthenticated_access

   def new
     @user = User.new
   end

   def create
     @user = User.new(user_params)

     if @user.save
       start_new_session_for @user
       redirect_to edit_profile_path, notice: "Welcome! Set up your profile so we can personalise your workouts."
     else
       render :new, status: :unprocessable_entity
     end
   end

   private

   def user_params
     params.expect(user: [ :email_address, :password ])
   end
 end