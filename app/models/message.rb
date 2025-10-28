class Message < ApplicationRecord
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  belongs_to :chat

  validates :number, presence: true, uniqueness: { scope: :chat_id }
  validates :body, presence: true

  # Elasticsearch settings
  settings do
    mapping do
      indexes :body, type: :text, analyzer: :standard
      indexes :chat_id, type: :integer
    end
  end

  def as_indexed_json(options = {})
    as_json(only: [:id, :body, :chat_id, :created_at])
  end
end
