class Chat < ApplicationRecord
  belongs_to :chat_application
  has_many :messages, dependent: :destroy

  validates :number, presence: true, uniqueness: { scope: :chat_application_id }
end
