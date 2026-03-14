module User::GenerationQuota
  extend ActiveSupport::Concern

  included do
    has_many :generation_uses, dependent: :destroy
  end

  def generations_this_week
    generation_uses.where(created_at: 1.week.ago..).count
  end

  def generation_limit_reached?
    free? && generations_this_week >= self.class::FREE_GENERATION_LIMIT
  end

  def generations_remaining
    return nil if pro?
    [ self.class::FREE_GENERATION_LIMIT - generations_this_week, 0 ].max
  end
end
