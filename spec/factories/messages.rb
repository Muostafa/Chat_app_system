FactoryBot.define do
  factory :message do
    chat
    number { 1 }
    body { Faker::Lorem.sentence }
  end
end
