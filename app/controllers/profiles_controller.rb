class ProfilesController < ApplicationController
  before_action :require_authentication

  # PB keys stored as seconds (time events), kg (lifts), or reps (counts)
  TIME_PB_KEYS = %w[
    run_5km run_10km run_half_marathon run_1mile run_1_5mile
    swim_100m_fc swim_400m swim_1500m swim_1mile
    row_500m row_1000m row_2000m
    ski_500m ski_2000m
    assault_bike_50cal assault_bike_100cal
    floor_to_ceiling_30 thrusters_50
    wall_balls_100 hyrox_race deka_fit
  ].freeze

  WEIGHT_PB_KEYS = %w[bench_1rm squat_1rm deadlift_1rm clean_jerk_1rm snatch_1rm].freeze
  COUNT_PB_KEYS  = %w[press_ups_2min pull_ups_max burpees_1min].freeze

  EQUIPMENT_OPTIONS = %w[
    ski_erg rowing_machine assault_bike bike_erg treadmill
    pull_up_bar barbell dumbbells kettlebells
    sled sandbag atlas_stones resistance_bands
    swimming_pool open_water
  ].freeze

  def show
    @user = Current.user
  end

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    @user.assign_attributes(profile_params)
    @user.equipment = Array(params[:user][:equipment]).reject(&:blank?)
    @user.personal_bests = parse_personal_bests(params[:personal_bests] || {})

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
      :pool_length, :run_preference
    )
  end

  def parse_personal_bests(pb_params)
    result = @user.personal_bests.dup || {}

    TIME_PB_KEYS.each do |key|
      raw = pb_params[key].to_s.strip
      if raw.blank?
        result.delete(key)
      elsif raw.include?(":")
        parts = raw.split(":").map(&:to_i)
        secs = parts.length == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1]
        result[key] = secs if secs > 0
      elsif raw.to_i > 0
        result[key] = raw.to_i
      end
    end

    WEIGHT_PB_KEYS.each do |key|
      val = pb_params[key].to_f
      val > 0 ? result[key] = val : result.delete(key)
    end

    COUNT_PB_KEYS.each do |key|
      val = pb_params[key].to_i
      val > 0 ? result[key] = val : result.delete(key)
    end

    result
  end
end
