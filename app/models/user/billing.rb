module User::Billing
  extend ActiveSupport::Concern

  def pro?
    plan == "pro"
  end

  def free?
    plan == "free"
  end
end
