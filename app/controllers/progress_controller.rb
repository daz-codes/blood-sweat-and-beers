class ProgressController < ApplicationController
  before_action :require_authentication

  # GET /progress — curated test list with bests
  def index
    entries = Current.user.fitness_test_entries.all.to_a
    @entries_by_key = entries.group_by(&:test_key)
  end

  # GET /progress/:test_key
  def show
    @test = FitnessTests.find(params[:test_key])
    return redirect_to progress_path, alert: "Unknown test." unless @test

    @entries = Current.user.fitness_test_entries
                           .for_test(@test[:key])
                           .chronological

    @chart_data = @entries.map { |e| [ e.recorded_on.to_s, e.value.to_f ] }.to_h
    @best       = best_entry(@entries, @test)
    @new_entry  = FitnessTestEntry.new(recorded_on: Date.current)
  end

  # POST /progress/:test_key/entries
  def create_entry
    @test = FitnessTests.find(params[:test_key])
    return redirect_to progress_path, alert: "Unknown test." unless @test

    value = parse_value(params[:value], @test[:unit])

    if value.nil? || value <= 0
      redirect_to progress_test_path(@test[:key]),
        alert: "Invalid value — #{input_hint(@test[:unit])}"
      return
    end

    recorded_on = Date.parse(params[:recorded_on].presence || Date.current.to_s) rescue Date.current

    Current.user.fitness_test_entries.create!(
      test_key:    @test[:key],
      value:       value,
      recorded_on: recorded_on
    )

    redirect_to progress_test_path(@test[:key]), notice: "Result saved."
  end

  private

  def best_entry(entries, test)
    return nil if entries.empty?
    test[:scoring] == :lower ? entries.min_by(&:value) : entries.max_by(&:value)
  end

  # Parse "3:45" → 225, "1:03:45" → 3825, "225" → 225 for time
  # Otherwise just parse as float
  def parse_value(raw, unit)
    raw = raw.to_s.strip
    return nil if raw.blank?

    if unit == "time"
      case raw
      when /\A(\d+):(\d{2}):(\d{2})\z/
        $1.to_i * 3600 + $2.to_i * 60 + $3.to_i
      when /\A(\d+):(\d{2})\z/
        $1.to_i * 60 + $2.to_i
      when /\A\d+(\.\d+)?\z/
        raw.to_f
      end
    else
      v = raw.to_f
      v > 0 ? v : nil
    end
  end

  def input_hint(unit)
    unit == "time" ? "enter time as mm:ss or h:mm:ss" : "enter a number"
  end
end
