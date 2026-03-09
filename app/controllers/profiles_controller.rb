class ProfilesController < ApplicationController
  before_action :require_authentication

  EQUIPMENT_OPTIONS = %w[
    ski_erg rowing_machine assault_bike bike_erg treadmill
    pull_up_bar barbell dumbbells kettlebells
    sled sandbag atlas_stones resistance_bands
    swimming_pool open_water
  ].freeze

  def show
    @user = Current.user
    entries = Current.user.fitness_test_entries.where(test_key: FitnessTests::BENCHMARK_KEYS)
    @best_by_key = FitnessTests::BENCHMARKS.each_with_object({}) do |test, h|
      relevant = entries.select { |e| e.test_key == test[:key] }
      h[test[:key]] = test[:scoring] == :lower ? relevant.min_by(&:value) : relevant.max_by(&:value)
    end
  end

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    @user.assign_attributes(profile_params)
    @user.equipment = Array(params[:user][:equipment]).reject(&:blank?)

    if @user.save
      redirect_to profile_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(
      :username, :display_name,
      :age, :height_cm, :weight_kg, :gender,
      :pool_length
    )
  end
end
