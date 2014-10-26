enable :sessions
set :session_secret, ENV['SESSION_SECRET']

ActiveRecord::Base.configurations = YAML.load_file('database.yml')
ActiveRecord::Base.establish_connection(ENV['RACK_ENV'].to_sym)
use ActiveRecord::ConnectionAdapters::ConnectionManagement

def api_client; settings.api_client end
def gmail_api; settings.gmail end
def oauth_api; settings.oauth2 end

def current_user
  User.find(session[:user_id]) if session[:user_id]
end

def user_credentials
  @authorization ||= (
    token_hash = session[:user_id] ? User.find(session[:user_id]).token_hash : {}
    auth = api_client.authorization.dup
    auth.redirect_uri = to('/oauth2callback')
    auth.update_token!(token_hash)
    auth
  )
end

configure do
  client = Google::APIClient.new(:application_name => 'bye bye email test', :application_version => '1.0.0')
  client_secrets = Google::APIClient::ClientSecrets.load
  client.authorization = client_secrets.to_authorization
  client.authorization.scope = ['https://mail.google.com/',
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/userinfo.email']


  gmail = client.discovered_api('gmail', 'v1')
  oauth = client.discovered_api('oauth2', 'v2')

  set :api_client, client
  set :gmail, gmail
  set :oauth2, oauth
end

before do
  pass if %w(logout auto_update).include? request.path_info.split('/')[1]
  unless user_credentials.access_token || request.path_info =~ /\A\/oauth2/
    redirect to('/oauth2authorize')
  end
end

after do
  if user_credentials.refresh_token && user_credentials.expired?
    user_credentials.fetch_access_token!
    if current_user
      current_user.update_token!(user_credentials)
    end
  end
end

get '/logout' do
  session[:user_id] = nil
  redirect '/'
end

get '/oauth2authorize' do
  # Request authorization
  redirect user_credentials.authorization_uri.to_s, 303
end

get '/oauth2callback' do
  # Exchange token
  user_credentials.code = params[:code] if params[:code]
  user_credentials.fetch_access_token!
  user_info = api_client.execute(api_method: oauth_api.userinfo.get,
                                 parameters: { 'fields' => 'email' },
                                 authorization: user_credentials)
  email_address = JSON.parse(user_info.body)["email"]
  user = User.find_or_initialize_by(email: email_address)
  if user_credentials.refresh_token && user_credentials.expired?
    user_credentials.fetch_access_token!
  end
  if user.new_record? && user_credentials.refresh_token.nil?
    <<-EOS
すでにApplicationが認証済みでしたが、Userレコードが見つかりませんでした。
お手数ですがGoogleのアカウント管理画面へ行き、アクセス権を一旦解除してください。
    EOS
  else
    user.update_token!(user_credentials)
    session[:user_id] = user.id
    redirect to('/')
  end
end

# get '/compare' do
#   user_info = api_client.execute(api_method: oauth2_api.userinfo.get,
#                                  parameters: { 'fields' => 'email' },
#                                  authorization: user_credentials)
#   user_id = JSON.parse(user_info.body)["email"]
#
#   DIFF_THRESH = 0.8
#   LABEL_NAME  = '[BBmail]/shared'
#
#   @same_msgs = []
#   Gmail.where(email: user_id).each do |mail|
#     Gmail.where("email != ?", user_id).each do |another_mail|
#       unchanged = Diffy::Diff.new(mail.body, another_mail.body, allow_empty_diff: false)
#                              .each_chunk
#                              .reject{|part| part.match(/^(\+|-)/)}
#                              .first
#       if unchanged && (unchanged.length > (mail.body.length * DIFF_THRESH))
#         @same_msgs << [mail.id, another_mail.id, unchanged]
#       end
#     end
#   end
#
#   api_client.execute(api_method:  gmail_api.users.labels.create,
#                      parameters:  {'userId' => 'me'},
#                      body_object: {'messageListVisibility' => 'hide',
#                                    'labelListVisibility'   => 'labelShow',
#                                    'name' => LABEL_NAME},
#                      authorization: user_credentials)
#   #[FIXME] only call when label_name not exist
#
#   batch = Google::APIClient::BatchRequest.new
#   @same_msgs.each do |msg_arr|
#     dup_msg_id = Gmail.find(msg_arr.first).mail_id
#     batch.add(api_method: gmail_api.users.messages.modify,
#               parameters:  { 'id' => dup_msg_id,
#                              'userId' => 'me'},
#               body_object: {'removeLabelIds' => [],
#                             'addLabelIds'    => ['INBOX']},
#               authorization: user_credentials)
#   end
#   api_client.execute(batch, authorization: user_credentials)
#   # unless result.status == 200
#   #   puts "unsuccessful api call when trying to modify labels"
#   #   byebug
#   # end
#
#   erb :compare
# end

get '/' do
  user = current_user

  @current_user = user
  ignoring_mails = Message.where("ignored_at IS NOT NULL").pluck(:from_mail).uniq
  search_targets = Message.where("user_id != ?", user.id)

  # [TODO] メッセージ全体のインポートの保存期間を設定して、
  # 現在共有中の人を全員updateし終わっても同じ duplicateが見つからなかったら、それ以外の
  # メールは削除する

  # [TODO] 全文検索エンジン試す
  # [TODO] Fwd と Reの違いを許容するオプションモード検討する
  # Differ.diff_by_char(mail.subject, another_mail.subject).instance_variable_get(:@raw).last
  @thread_hash = {}
  rule_for_match = "message_protocol_id"
  your_msgs = if ignoring_mails != []
                user.messages.where("from_mail NOT IN (?)", ignoring_mails)
              else
                user.messages
              end
  your_msgs.each do |mail|
    if same_mails = search_targets.where("#{rule_for_match} = ?", mail.read_attribute(rule_for_match))
      if same_mails != []
        @thread_hash[mail.thread_id] = same_mails.pluck(:user_id) + [user.id]
      end
    end
  end

  @ongoing_threads_hash = {}
  @msgs_arr = []
  @thread_hash.each do |thread_id, shared_with_user_ids|
    msg_hash = {}
    msg_hash[:msgs]                = Message.where(thread_id: thread_id).order('sent_date')
    msg_hash[:assigned_to]         = Message.who_replied(msg_hash[:msgs])
    msg_hash[:shared_with_user_ids] = shared_with_user_ids
    if msg_hash[:assigned_to] && msg_hash[:msgs].last.from_mail != msg_hash[:assigned_to].email
      @ongoing_threads_hash[msg_hash[:assigned_to].id] = @ongoing_threads_hash.fetch(msg_hash[:assigned_to].id, 0) + 1
    end
    @msgs_arr << msg_hash
  end

  @comparing_user = User.find_by(id: params[:id])
  @only_new = params[:id] ? false : true

  @time = Time.now
  @time_til_next_sync = Time.mktime(@time.year,@time.month,@time.day,@time.hour)+3600
  erb :shared_msgs
end

get '/ignoring' do
  ignoring_mails = Message.where("ignored_at IS NOT NULL").pluck(:from_mail).uniq
  @current_user = current_user
  @msgs_arr = []
  ignoring_mails.each do |from_mail|
    @msgs_arr << Message.where(from_mail: from_mail).group(:subject).order('sent_date ASC')
  end
  erb :ignorings
end

get '/auto_update' do
  User.all.each do |user|
    @authorization = (
      auth = api_client.authorization.dup
      auth.redirect_uri = to('/oauth2callback')
      auth.update_token!(user.token_hash)
      auth
    )
    messages_arr, last_history_id = fetch_latest_msgs(user)
    puts "#{user.id}, #{last_history_id}"
    if messages_arr.nil?
      puts 'latest status'
    else
      messages = messages_arr.flatten
      get_and_save_msgs(messages,user)
      user.update_attributes!(latest_thread_history_id: last_history_id)
    end
  end
  "update finished\n"
end

get '/update' do
  user = current_user
  if user.latest_thread_history_id
    messages_arr, last_history_id = fetch_latest_msgs(user)
    if messages_arr.nil?
      puts 'latest status'
      redirect '/'
      return
    else
      messages = messages_arr.flatten
      get_and_save_msgs(messages,user)
      user.update_attributes!(latest_thread_history_id: last_history_id)
    end
  end
  redirect '/'
end

post '/ignore' do
  msg = Message.find params[:id]
  if params[:reverse]
    msgs_from_same_email = Message.where(from_mail: msg.from_mail)
    msgs_from_same_email.update_all(ignored_at: nil)
  else
    msg.update_attributes!(ignored_at: Time.now)
  end
  redirect '/'
end

post '/solve' do
  msg = Message.find params[:id]
  if msg.solved_at
    raise "solved msgを再度solveはできません"
  end
  same_msgs_in_others = Message.where(message_protocol_id: msg.message_protocol_id)
  same_msgs_in_others.each do |same_msg|
    solve_stab_msg = Message.new(
      solved_at: Time.now,
      user_id:   msg.user_id,
      thread_id: same_msg.thread_id,
      snippet:   "solved by #{msg.user.email} at #{Time.now}",
      from_mail: msg.user.email,
      sent_date: Time.now,
      headers:   "",
      mail_id:   "",
      message_protocol_id: "",
    )
    solve_stab_msg.save!
  end
  redirect '/'
end

get '/import' do
  user = current_user
  result = api_client.execute(api_method: gmail_api.users.threads.list,
                              parameters: { 'userId' => 'me', 'q' => 'is:inbox' },
                              authorization: user_credentials)
  unless result.status == 200
    return JSON.parse(result.body).to_json
  end
  thread_list_response = JSON.parse result.body

  batch = Google::APIClient::BatchRequest.new
  thread_list_response["threads"].each do |thread|
    batch.add(api_method: gmail_api.users.threads.get,
              parameters: { 'id' => thread["id"], 'userId' => 'me'},
              authorization: user_credentials)
  end
  result = api_client.execute(batch, authorization: user_credentials)
  unless result.status == 200
    return JSON.parse(result.body).to_json
  end
  boundary = result.headers["content-type"].split(/boundary=/).last
  result.body.split(boundary).each do |could_be_thread|
    if could_be_thread.match(/{.+}/m)
      json_body = could_be_thread.match(/{.+}/m)[0]
      thread = JSON.parse(json_body)
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
  user.latest_thread_history_id = thread_list_response["threads"].first["historyId"]
  user.last_thread_next_page_token = thread_list_response["nextPageToken"]
  user.save!

  redirect '/'
end

def fetch_latest_msgs(user)
  client_call = Proc.new do |pageToken|
    api_client.execute(api_method: gmail_api.users.history.list,
                       parameters: { 'userId'  => 'me',
                         'startHistoryId' => user.latest_thread_history_id.to_s,
                         'pageToken'      => pageToken },
                         authorization: user_credentials )
  end
  results = []
  result = client_call.call(nil)
  json = JSON.parse(result.body)
  results << json
  while nextPageToken = json["nextPageToken"]
    result = client_call.call(nextPageToken)
    json = JSON.parse(result.body)
    results << json
  end

  last_history_id = results.last["historyId"].to_i
  messages = if results.none?{|res| res["history"]}
               nil
             else
               results.inject([]) do |sum,res|
                 sum << res["history"].map{|r| r["messages"]}.flatten.compact
               end
             end
  [messages, last_history_id]
end

def get_and_save_msgs(messages, user)
  batch = Google::APIClient::BatchRequest.new
  messages.flatten.each do |msg|
    begin
      batch.add(api_method: gmail_api.users.messages.get,
                parameters: { 'id' => msg["id"], 'userId' => 'me'},
                authorization: user_credentials)
    rescue => e
      puts e
    end
  end
  result = api_client.execute(batch, authorization: user_credentials)

  boundary = result.headers["content-type"].split(/boundary=/).last
  result.body.split(boundary).each do |could_be_msg|
    if could_be_msg.match(/{.+}/m)
      json_body = could_be_msg.match(/{.+}/m)[0]
      msg = JSON.parse(json_body)
      msg_record = user.messages.find_or_initialize_by(mail_id: msg["id"])
      msg_record.update_with_msg!(msg)
    end
  end
end

def stat(thread, person)
  diffs = []
  thread.msgs.each do |msg|
    i = 1
    msg_i = msgs.index(msg)
    begin
      next_in = msgs[msg_i + i]
      i += 1
    end while person.group.include?(msgs[msg_i + i].from)

    diffs << (next_in.date - msg.date)
  end

  response_time_average = diffs.inject(:+) / diffs.count
  return response_time_average
end
