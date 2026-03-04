module ApplicationHelper
  # Total distance in metres for a single workout section.
  # Handles straight/rounds sections (sum of exercise distance_m × rounds)
  # and ladder/mountain sections (distances derived from start/end/step × num exercises).
  def section_distance_m(section)
    rounds = [section["rounds"].to_i, 1].max
    if %w[ladder mountain].include?(section["format"].to_s) && section["varies"] == "distance_m"
      step = [section["step"].to_f, 1.0].max
      vals = []
      if section["format"] == "ladder"
        sv = section["start"].to_f; ev = section["end"].to_f
        if sv <= ev
          v = sv; while v <= ev + 0.001; vals << v; v += step; end
        else
          v = sv; while v >= ev - 0.001; vals << v; v -= step; end
        end
      else # mountain
        sv = section["start"].to_f; pk = section["peak"].to_f; ev = section["end"].to_f
        v = sv; while v <= pk + 0.001; vals << v; v += step; end
        v = pk - step; while v >= ev - 0.001; vals << v; v -= step; end
      end
      n = [Array(section["exercises"]).length, 1].max
      vals.sum.to_i * n
    else
      Array(section["exercises"]).sum { |e| e["distance_m"].to_i } * rounds
    end
  end
end
