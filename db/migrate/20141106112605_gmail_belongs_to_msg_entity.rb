class GmailBelongsToMsgEntity < ActiveRecord::Migration
  def change
    add_column :messages, :msg_entity_id, :integer
  end
end
