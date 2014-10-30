# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 0) do

  create_table "duplicates", force: true do |t|
    t.string   "dup_mail_id",         null: false
    t.string   "another_dup_mail_id", null: false
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
  end

  create_table "labels", force: true do |t|
    t.string   "name"
    t.string   "id_on_gmail", null: false
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
  end

  create_table "message_has_labels", force: true do |t|
    t.integer "label_id",   null: false
    t.integer "message_id", null: false
  end

  create_table "messages", force: true do |t|
    t.integer  "user_id",             null: false
    t.string   "thread_id",           null: false
    t.string   "snippet",             null: false
    t.string   "from_mail",           null: false
    t.datetime "sent_date",           null: false
    t.string   "subject"
    t.text     "headers",             null: false
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
    t.string   "mail_id",             null: false
    t.string   "message_protocol_id", null: false
    t.datetime "ignored_at"
    t.datetime "solved_at"
  end

  create_table "users", force: true do |t|
    t.string   "email",                       null: false
    t.string   "access_token",                null: false
    t.integer  "expires_in"
    t.string   "refresh_token",               null: false
    t.integer  "issued_at"
    t.integer  "latest_thread_history_id"
    t.datetime "created_at",                  null: false
    t.datetime "updated_at",                  null: false
    t.string   "last_thread_next_page_token"
  end

end
