class Message < ActiveRecord::Base
  has_many :message_has_labels
  has_many :labels, through: :message_has_labels
  belongs_to :user

  def self.who_replied(msgs)
    index = 0
    begin
     replied_by_who = msgs.order('sent_date DESC').offset(index).limit(1).first
     if replied_by_who.nil?
       return nil
     end
     replied_by_who_mail = replied_by_who.from_mail
     index += 1
    end while !User.exists?(email: replied_by_who_mail)
    User.find_by(email: replied_by_who_mail)
  end

  def update_with_msg!(obj)
    self.snippet   = obj["snippet"]
    self.thread_id = obj["threadId"]
    self.sent_date = Time.parse(obj["payload"]["headers"].detect{|header| header["name"] == "Date" }["value"])
    self.subject   = obj["payload"]["headers"].detect{|header| header["name"] == "Subject" }["value"]
    self.headers   = obj["payload"]["headers"]

    from_mail = obj["payload"]["headers"].detect{|header|
                  header["name"] == "From"
                }["value"].match(/[a-z0-9+_.-]+@([a-z0-9-]+\.)+[a-z]{2,4}/i)[0]
    self.from_mail = from_mail

    message_protocol_id = obj["payload"]["headers"].detect{|header|
      %w(Message-ID Message-Id Message-id).include?(header["name"])
    }["value"].match(/[^<>]+@[^<>]+/i)[0]
    self.message_protocol_id = message_protocol_id

    msg_payload = obj["payload"]
    while msg_payload["body"]["size"].to_i == 0
      msg_payload = msg_payload["parts"].first
    end
    msg_body = Base64.urlsafe_decode64 msg_payload["body"]["data"]
    self.body = msg_body

    begin
      self.labels = []
      obj["labelIds"] && obj["labelIds"].each do |label_id|
        self.labels << Label.find_or_create_by(id_on_gmail: label_id)
      end
    rescue => e
      puts e
      byebug
    end

    self.save!
  end
end
