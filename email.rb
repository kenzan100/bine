require 'rubygems'
require 'bundler'

Bundler.require

require 'active_record'
require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/file_storage'
require 'sinatra/reloader' if development?
require 'logger'

enable :sessions

CREDENTIAL_STORE_FILE = "#{$0}-oauth2.json"

ActiveRecord::Base.configurations = YAML.load_file('database.yml')
ActiveRecord::Base.establish_connection(:development)

class Gmail < ActiveRecord::Base
end

class Duplicate < ActiveRecord::Base
end

def logger; settings.logger end
def api_client; settings.api_client; end
def gmail_api; settings.gmail; end

def user_credentials
  # Build a per-request oauth credential based on token stored in session
  # which allows us to use a shared API client.
  @authorization ||= (
    auth = api_client.authorization.dup
    auth.redirect_uri = to('/oauth2callback')
    auth.update_token!(session)
    auth
  )
end

configure do
  log_file = File.open('bye_bye_email.log', 'a+')
  log_file.sync = true
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG

  client = Google::APIClient.new(
    :application_name => 'bye bye email test',
    :application_version => '1.0.0'
  )

  file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
  if file_storage.authorization.nil?
    client_secrets = Google::APIClient::ClientSecrets.load
    client.authorization = client_secrets.to_authorization
    client.authorization.scope = 'https://www.googleapis.com/auth/gmail.readonly'
  else
    client.authorization = file_storage.authorization
  end

  # Since we're saving the API definition to the settings, we're only retrieving
  # it once (on server start) and saving it between requests.
  # If this is still an issue, you could serialize the object and load it on
  # subsequent runs.
  gmail = client.discovered_api('gmail', 'v1')

  set :logger, logger
  set :api_client, client
  set :gmail, gmail
end

before do
  # Ensure user has authorized the app
  unless user_credentials.access_token || request.path_info =~ /\A\/oauth2/
    redirect to('/oauth2authorize')
  end
end

after do
  # Serialize the access/refresh token to the session and credential store.
  session[:access_token] = user_credentials.access_token
  session[:refresh_token] = user_credentials.refresh_token
  session[:expires_in] = user_credentials.expires_in
  session[:issued_at] = user_credentials.issued_at

  file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
  file_storage.write_credentials(user_credentials)
end

get '/oauth2authorize' do
  # Request authorization
  redirect user_credentials.authorization_uri.to_s, 303
end

get '/oauth2callback' do
  # Exchange token
  user_credentials.code = params[:code] if params[:code]
  user_credentials.fetch_access_token!
  redirect to('/')
end

get '/' do
  result = api_client.execute(api_method: gmail_api.users.messages.list,
                              parameters: { 'userId' => 'me' },
                              authorization: user_credentials)
  unless result.status == 200
    return JSON.parse(result.body).to_json
  end
  response = JSON.parse result.body
  mail_ids = response["messages"].map do |hash|
    hash["id"]
  end

  batch = Google::APIClient::BatchRequest.new
  mail_ids[0..1].each do |id|
    batch.add(api_method: gmail_api.users.messages.get,
              parameters: { 'id' => id, 'userId' => 'me'}, #, 'format' => 'raw' },
              authorization: user_credentials)

  end
  result = api_client.execute(batch)
  boundary = result.headers["content-type"].split(/boundary=/).last
  result.body.split(boundary).each do |could_be_msg|
    if could_be_msg.match(/{.+}/m)
      json_body = could_be_msg.match(/{.+}/m)[0]
      msg = JSON.parse(json_body)
      body = msg["payload"]["parts"] ? msg["payload"]["parts"].first : msg["payload"]
      Gmail.find_or_create_by_mail_id(msg["id"],
        snippet: msg["snippet"],
        email:   msg["payload"]["headers"][0]["value"],
        headers: msg["payload"]["headers"],
        body:    Base64.urlsafe_decode64(body["body"]["data"])
      )
    end
  end
  @msgs = Gmail.all
end
