FactoryBot.define do
  factory :chat do
    chat_application
    number { 1 }
    messages_count { 0 }
  end
end
