module ProgressHelper
  def format_test_value(value, unit)
    return "—" if value.nil?
    v = value.to_f
    case unit
    when "time"
      secs = v.to_i
      h = secs / 3600
      m = (secs % 3600) / 60
      s = secs % 60
      h > 0 ? "%d:%02d:%02d" % [ h, m, s ] : "%d:%02d" % [ m, s ]
    when "m"      then "#{v.to_i}m"
    when "kg"     then v == v.to_i ? "#{v.to_i}kg" : "#{"%.1f" % v}kg"
    when "reps"   then "#{v.to_i} reps"
    when "cal"    then "#{v.to_i} cal"
    when "rounds" then v == v.to_i ? "#{v.to_i} rounds" : "#{"%.1f" % v} rounds"
    else v.to_s
    end
  end

  def input_placeholder(unit)
    case unit
    when "time"   then "e.g. 3:45"
    when "m"      then "e.g. 2400"
    when "kg"     then "e.g. 120"
    when "reps"   then "e.g. 42"
    when "cal"    then "e.g. 85"
    when "rounds" then "e.g. 18"
    else "value"
    end
  end

  def unit_label(unit)
    case unit
    when "time"   then "mm:ss"
    when "m"      then "metres"
    when "kg"     then "kg"
    when "reps"   then "reps"
    when "cal"    then "calories"
    when "rounds" then "rounds"
    end
  end

  def chart_ytitle(unit)
    case unit
    when "time"   then "seconds"
    when "m"      then "metres"
    when "kg"     then "kg"
    when "reps"   then "reps"
    when "cal"    then "calories"
    when "rounds" then "rounds"
    end
  end
end
