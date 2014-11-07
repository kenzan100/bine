class GmailEntity < ActiveRecord::Base
  has_many :message_has_labels, foreign_key: :message_id
  has_many :labels, through: :message_has_labels
  belongs_to :user
  belongs_to :msg_entity

  def self.who_replied(msgs, user_emails)
    index = 0
    begin
     replied_by_who = msgs.map(&:msg_entity).sort_by{|msg| msg.sent_date}.reverse[index]
     if replied_by_who.nil?
       return nil
     end
     replied_by_who_mail = replied_by_who.from_mail
     index += 1
    end while !user_emails.include?(replied_by_who_mail)
    return replied_by_who_mail
  end

  def update_with_msg!(obj)
    self.thread_id = obj["threadId"]
    self.headers   = obj["payload"]["headers"]
    self.mail_id   = obj["id"]

    GmailEntity.transaction do
      self.save!
      from_mail           = obj["payload"]["headers"].detect{|header|
                              header["name"] == "From"
                            }["value"].match(/[a-z0-9+_.-]+@([a-z0-9-]+\.)+[a-z]{2,4}/i)[0]
      message_protocol_id = obj["payload"]["headers"].detect{|header|
                              %w(Message-ID Message-Id Message-id).include?(header["name"])
                            }["value"].match(/[^<>]+@[^<>]+/i)[0]

      msg_entity_record = MsgEntity.find_or_create_by!(message_protocol_id: message_protocol_id) do |msg_entity|
        msg_entity.snippet   = obj["snippet"]
        msg_entity.from_mail = from_mail
        msg_entity.sent_date = Time.parse(obj["payload"]["headers"].detect{|header| header["name"] == "Date" }["value"])
        msg_entity.subject   =  obj["payload"]["headers"].detect{|header| header["name"] == "Subject" }["value"]
      end
      self.msg_entity = msg_entity_record
      self.save!

      # This saves body as well
      # msg_payload = obj["payload"]
      # while msg_payload["body"]["size"].to_i == 0
      #   msg_payload = msg_payload["parts"].first
      # end
      # msg_body = Base64.urlsafe_decode64 msg_payload["body"]["data"]
      # self.body = msg_body

      begin
        self.labels = []
        obj["labelIds"] && obj["labelIds"].each do |label_id|
          self.labels << Label.find_or_create_by!(id_on_gmail: label_id)
        end
      rescue => e
        puts e
      end
    end
  end
end
