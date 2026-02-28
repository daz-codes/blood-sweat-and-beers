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

ActiveRecord::Schema[8.2].define(version: 2026_02_28_101725) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_log_id", null: false
    t.index ["user_id"], name: "index_comments_on_user_id"
    t.index ["workout_log_id", "created_at"], name: "index_comments_on_workout_log_id_and_created_at"
    t.index ["workout_log_id"], name: "index_comments_on_workout_log_id"
  end

  create_table "exercise_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exercise_id"
    t.jsonb "sets_data", default: [], null: false
    t.integer "step_order", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_log_id", null: false
    t.index ["exercise_id"], name: "index_exercise_logs_on_exercise_id"
    t.index ["sets_data"], name: "index_exercise_logs_on_sets_data", using: :gin
    t.index ["step_order"], name: "index_exercise_logs_on_step_order"
    t.index ["workout_log_id"], name: "index_exercise_logs_on_workout_log_id"
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "defaults", default: {}
    t.integer "deka_station_order"
    t.string "equipment"
    t.string "format_tags", default: [], array: true
    t.integer "hyrox_station_order"
    t.string "metric", default: "reps", null: false
    t.string "movement_type", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.bigint "follower_id", null: false
    t.bigint "following_id", null: false
    t.datetime "requested_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["follower_id", "following_id"], name: "index_follows_on_follower_id_and_following_id", unique: true
    t.index ["follower_id", "status"], name: "index_follows_on_follower_id_and_status"
    t.index ["follower_id"], name: "index_follows_on_follower_id"
    t.index ["following_id", "status"], name: "index_follows_on_following_id_and_status"
    t.index ["following_id"], name: "index_follows_on_following_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tag_id", null: false
    t.bigint "taggable_id", null: false
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
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "workout_likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_id", null: false
    t.index ["user_id", "workout_id"], name: "index_workout_likes_on_user_id_and_workout_id", unique: true
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
    t.bigint "user_id", null: false
    t.string "visibility", default: "public", null: false
    t.bigint "workout_id", null: false
    t.index ["completed_at"], name: "index_workout_logs_on_completed_at"
    t.index ["user_id"], name: "index_workout_logs_on_user_id"
    t.index ["visibility"], name: "index_workout_logs_on_visibility"
    t.index ["workout_id"], name: "index_workout_logs_on_workout_id"
  end

  create_table "workouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "difficulty", default: "intermediate", null: false
    t.integer "duration_mins", null: false
    t.string "name"
    t.bigint "source_workout_id"
    t.string "status", default: "active", null: false
    t.jsonb "structure", default: [], null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "workout_type", null: false
    t.index ["source_workout_id"], name: "index_workouts_on_source_workout_id"
    t.index ["status"], name: "index_workouts_on_status"
    t.index ["structure"], name: "index_workouts_on_structure", using: :gin
    t.index ["user_id"], name: "index_workouts_on_user_id"
    t.index ["workout_type"], name: "index_workouts_on_workout_type"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "comments", "users"
  add_foreign_key "comments", "workout_logs"
  add_foreign_key "exercise_logs", "exercises"
  add_foreign_key "exercise_logs", "workout_logs"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "follows", "users", column: "following_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "taggings", "tags"
  add_foreign_key "workout_likes", "users"
  add_foreign_key "workout_likes", "workouts"
  add_foreign_key "workout_logs", "users"
  add_foreign_key "workout_logs", "workouts"
  add_foreign_key "workouts", "users"
  add_foreign_key "workouts", "workouts", column: "source_workout_id"
end
