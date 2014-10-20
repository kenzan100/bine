class Label < ActiveRecord::Base
  has_many :message_has_labels
  has_many :messages, through: :message_has_labels
end
