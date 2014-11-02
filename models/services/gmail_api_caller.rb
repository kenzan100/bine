class GmailApiCaller
  def self.batch_res_split(batch_res)
    boundary = batch_res.headers["content-type"].split(/boundary=/).last
    batch_res.body.split(boundary)
  end

  def self.save_thread_get_batch_res(batch_res, user)
    batch_res_split(batch_res).each do |could_be_thread|
      if could_be_thread.match(/{.+}/m)
        json_body = could_be_thread.match(/{.+}/m)[0]
        thread = JSON.parse(json_body)
        if thread["messages"]
          begin
            thread["messages"].each do |msg|
              msg_record = user.messages.find_or_initialize_by(mail_id: msg["id"])
              msg_record.update_with_msg!(msg)
            end
          rescue => e
            puts e
          end
        end
      end
    end
  end
end
