namespace :seed_workouts do
  desc "Export workouts to db/seeds/workouts.json for use as seed data.\n\n" \
       "  rails seed_workouts:export                       # exports system user's workouts\n" \
       "  rails 'seed_workouts:export[you@example.com]'   # exports a specific user's workouts"
  task :export, [:email] => :environment do |_, args|
    email = args[:email].presence || "system@bloodsweatbeers.app"
    user  = User.find_by!(email_address: email)

    workouts = user.workouts.includes(:tags).order(:name).map do |w|
      {
        name:          w.name,
        workout_type:  w.workout_type,
        duration_mins: w.duration_mins,
        difficulty:    w.difficulty,
        tags:          w.tags.map(&:name),
        structure:     w.structure
      }
    end

    path = Rails.root.join("db/seeds/workouts.json")
    File.write(path, JSON.pretty_generate(workouts))

    puts "Exported #{workouts.size} workout(s) from #{email} → #{path}"
  end
end
