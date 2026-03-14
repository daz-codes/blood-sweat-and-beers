module User::FitnessTracking
  extend ActiveSupport::Concern

  included do
    has_many :fitness_test_entries, dependent: :destroy
  end

  def completed_benchmark_keys
    fitness_test_entries.where(test_key: FitnessTests::BENCHMARK_KEYS).distinct.pluck(:test_key).to_set
  end

  def benchmarks_complete?
    completed_benchmark_keys.size >= FitnessTests::BENCHMARK_KEYS.size
  end
end
