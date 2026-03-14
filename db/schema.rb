# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_03_14_170423) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_activities_on_name", unique: true
  end

  create_table "challenge_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "daily_challenge_id", null: false
    t.datetime "logged_at", null: false
    t.text "notes"
    t.boolean "rx", default: true, null: false
    t.decimal "score", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["daily_challenge_id"], name: "index_challenge_entries_on_daily_challenge_id"
    t.index ["user_id", "daily_challenge_id"], name: "index_challenge_entries_on_user_id_and_daily_challenge_id", unique: true
    t.index ["user_id"], name: "index_challenge_entries_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workout_log_id", null: false
    t.index ["user_id"], name: "index_comments_on_user_id"
    t.index ["workout_log_id", "created_at"], name: "index_comments_on_workout_log_id_and_created_at"
    t.index ["workout_log_id"], name: "index_comments_on_workout_log_id"
  end

  create_table "daily_challenges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "description", null: false
    t.string "scoring_type", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_daily_challenges_on_date", unique: true
  end

  create_table "exercise_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "exercise_id"
    t.json "sets_data", default: [], null: false
    t.integer "step_order", null: false
    t.datetime "updated_at", null: false
    t.integer "workout_log_id", null: false
    t.index ["exercise_id"], name: "index_exercise_logs_on_exercise_id"
    t.index ["step_order"], name: "index_exercise_logs_on_step_order"
    t.index ["workout_log_id"], name: "index_exercise_logs_on_workout_log_id"
  end

  create_table "exercise_videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.boolean "verified", default: false, null: false
    t.index ["slug"], name: "index_exercise_videos_on_slug", unique: true
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "defaults", default: {}
    t.integer "deka_station_order"
    t.string "equipment"
    t.json "format_tags", default: []
    t.integer "hyrox_station_order"
    t.string "metric", default: "reps", null: false
    t.string "movement_type", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "fitness_test_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "recorded_on", null: false
    t.string "test_key", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.decimal "value", precision: 12, scale: 3, null: false
    t.index ["user_id", "test_key", "recorded_on"], name: "idx_on_user_id_test_key_recorded_on_56491a2c50"
    t.index ["user_id"], name: "index_fitness_test_entries_on_user_id"
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.integer "follower_id", null: false
    t.integer "following_id", null: false
    t.datetime "requested_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["follower_id", "following_id"], name: "index_follows_on_follower_id_and_following_id", unique: true
    t.index ["follower_id", "status"], name: "index_follows_on_follower_id_and_status"
    t.index ["follower_id"], name: "index_follows_on_follower_id"
    t.index ["following_id", "status"], name: "index_follows_on_following_id_and_status"
    t.index ["following_id"], name: "index_follows_on_following_id"
  end

  create_table "generation_uses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_generation_uses_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_generation_uses_on_user_id"
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id", null: false
    t.datetime "created_at", null: false
    t.integer "notifiable_id", null: false
    t.string "notifiable_type", null: false
    t.datetime "read_at"
    t.integer "recipient_id", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["recipient_id", "created_at"], name: "index_notifications_on_recipient_id_and_created_at"
    t.index ["recipient_id", "read_at"], name: "index_notifications_on_recipient_id_and_read_at"
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
  end

  create_table "personal_records", force: :cascade do |t|
    t.datetime "achieved_at", null: false
    t.datetime "created_at", null: false
    t.string "exercise_name", null: false
    t.string "metric", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.decimal "value", precision: 10, scale: 2, null: false
    t.integer "workout_log_id", null: false
    t.index ["user_id", "exercise_name", "metric"], name: "index_prs_on_user_exercise_metric"
    t.index ["user_id"], name: "index_personal_records_on_user_id"
    t.index ["workout_log_id"], name: "index_personal_records_on_workout_log_id"
  end

  create_table "program_workouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "program_id", null: false
    t.text "session_notes"
    t.integer "session_number", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "week_number", null: false
    t.integer "workout_id"
    t.index ["program_id", "week_number", "session_number"], name: "index_program_workouts_on_program_week_session", unique: true
    t.index ["program_id"], name: "index_program_workouts_on_program_id"
    t.index ["workout_id"], name: "index_program_workouts_on_workout_id"
  end

  create_table "programs", force: :cascade do |t|
    t.integer "activity_id"
    t.datetime "created_at", null: false
    t.string "difficulty", default: "intermediate", null: false
    t.integer "duration_mins", null: false
    t.string "name", null: false
    t.integer "sessions_per_week", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "weeks_count", null: false
    t.index ["activity_id"], name: "index_programs_on_activity_id"
    t.index ["user_id", "created_at"], name: "index_programs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_programs_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", limit: 4, null: false
    t.datetime "created_at", null: false
    t.binary "key", limit: 1024, null: false
    t.integer "key_hash", limit: 8, null: false
    t.binary "value", limit: 536870912, null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "tag_id", null: false
    t.integer "taggable_id", null: false
    t.string "taggable_type", null: false
    t.index ["tag_id", "taggable_type", "taggable_id"], name: "index_taggings_on_tag_id_and_taggable_type_and_taggable_id", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "age"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.json "equipment", default: []
    t.json "exercise_weights", default: {}, null: false
    t.string "gender"
    t.integer "height_cm"
    t.string "password_digest"
    t.json "personal_bests", default: {}
    t.string "plan", default: "free", null: false
    t.string "pool_length"
    t.string "run_preference"
    t.datetime "updated_at", null: false
    t.string "username"
    t.decimal "weight_kg"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "workout_likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workout_id", null: false
    t.index ["user_id", "workout_id"], name: "index_workout_likes_on_user_id_and_workout_id"
    t.index ["user_id"], name: "index_workout_likes_on_user_id"
    t.index ["workout_id"], name: "index_workout_likes_on_workout_id"
  end

  create_table "workout_logs", force: :cascade do |t|
    t.integer "comments_count", default: 0, null: false
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.string "location"
    t.text "notes"
    t.integer "sweat_rating", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "visibility", default: "public", null: false
    t.integer "workout_id", null: false
    t.index ["completed_at"], name: "index_workout_logs_on_completed_at"
    t.index ["user_id"], name: "index_workout_logs_on_user_id"
    t.index ["visibility"], name: "index_workout_logs_on_visibility"
    t.index ["workout_id"], name: "index_workout_logs_on_workout_id"
  end

  create_table "workouts", force: :cascade do |t|
    t.integer "activity_id"
    t.datetime "created_at", null: false
    t.string "difficulty", default: "intermediate", null: false
    t.integer "duration_mins", null: false
    t.string "name"
    t.text "session_notes"
    t.integer "source_workout_id"
    t.string "status", default: "active", null: false
    t.json "structure", default: [], null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["activity_id"], name: "index_workouts_on_activity_id"
    t.index ["source_workout_id"], name: "index_workouts_on_source_workout_id"
    t.index ["status"], name: "index_workouts_on_status"
    t.index ["user_id"], name: "index_workouts_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "challenge_entries", "daily_challenges"
  add_foreign_key "challenge_entries", "users"
  add_foreign_key "comments", "users"
  add_foreign_key "comments", "workout_logs"
  add_foreign_key "exercise_logs", "exercises"
  add_foreign_key "exercise_logs", "workout_logs"
  add_foreign_key "fitness_test_entries", "users"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "follows", "users", column: "following_id"
  add_foreign_key "generation_uses", "users"
  add_foreign_key "identities", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "personal_records", "users"
  add_foreign_key "personal_records", "workout_logs"
  add_foreign_key "program_workouts", "programs"
  add_foreign_key "program_workouts", "workouts"
  add_foreign_key "programs", "activities"
  add_foreign_key "programs", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "taggings", "tags"
  add_foreign_key "workout_likes", "users"
  add_foreign_key "workout_likes", "workouts"
  add_foreign_key "workout_logs", "users"
  add_foreign_key "workout_logs", "workouts"
  add_foreign_key "workouts", "activities"
  add_foreign_key "workouts", "users"
  add_foreign_key "workouts", "workouts", column: "source_workout_id"
end
