desc "split_msgs"
task :split_msgs do
  Message.find_each do |msg|
    MsgEntity.find_or_create_by(message_protocol_id: msg.message_protocol_id) do |msg_entity|
      msg_entity.snippet   = msg.snippet
      msg_entity.from_mail = msg.from_mail
      msg_entity.sent_date = msg.sent_date
      msg_entity.subject   = msg.subject
      msg_entity.ignored_at = msg.ignored_at
      msg_entity.solved_at  = msg.solved_at
      msg_entity.created_at = msg.created_at
      msg_entity.updated_at = msg.updated_at
    end

    puts "-----#{MsgEntity.count}-----" if MsgEntity.count % 100 == 0
  end
end
