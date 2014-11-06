class SplitMessages < ActiveRecord::Migration
  def change
    create_table "msg_entities", force: true do |t|
      t.string   "snippet",             null: false
      t.string   "from_mail",           null: false
      t.datetime "sent_date",           null: false
      t.string   "subject"
      t.string   "message_protocol_id", null: false
      t.datetime "ignored_at"
      t.datetime "solved_at"
      t.datetime "created_at",          null: false
      t.datetime "updated_at",          null: false
    end
  end
end
