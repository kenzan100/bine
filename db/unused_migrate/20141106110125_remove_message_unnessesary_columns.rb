class RemoveMessageUnnessesaryColumns < ActiveRecord::Migration
  def change
    rename_table 'messages', 'gmail_entities'
    remove_columns :gmail_entities, :snippet,
                                    :from_mail,
                                    :sent_date,
                                    :subject,
                                    :message_protocol_id,
                                    :ignored_at,
                                    :solved_at
  end
end
