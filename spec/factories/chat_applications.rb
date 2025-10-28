FactoryBot.define do
  factory :chat_application do
    name { Faker::App.name }
    token { SecureRandom.hex(16) }
    chats_count { 0 }
  end
end
