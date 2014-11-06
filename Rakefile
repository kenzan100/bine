require 'sinatra/activerecord'
require 'sinatra/activerecord/rake'
require_relative 'models/init'

ActiveRecord::Base.configurations = YAML.load_file('database.yml')
ActiveRecord::Base.establish_connection(ENV['RACK_ENV'].to_sym)

Dir.glob('lib/tasks/*.rake').each { |r| load r}
