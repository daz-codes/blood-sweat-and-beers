module Workout::Likeable
  extend ActiveSupport::Concern

  included do
    has_many :workout_likes, dependent: :destroy
  end

  class_methods do
    def most_liked_with_activity(activity, limit: 25)
      scope = if activity.is_a?(Activity)
        where(activity: activity)
      else
        joins(:activity).where(activities: { name: activity })
      end
      scope.left_joins(:workout_likes)
           .group(:id)
           .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
           .limit(limit)
    end
  end
end
