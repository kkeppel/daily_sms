class ClientProfile < Sequel::Model
  one_to_one :client
end