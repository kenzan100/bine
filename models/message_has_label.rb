class MessageHasLabel < ActiveRecord::Base
  belongs_to :label
  belongs_to :message
end
