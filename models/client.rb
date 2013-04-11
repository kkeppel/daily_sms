class Client < Sequel::Model
  one_to_many :order_request
  many_to_one :company
  one_to_one :client_profile
  
  def name
    company.name
  end
  def address
    (client_profile.delivery_address.strip.length > 1) ? client_profile.delivery_address : company.address
  end
  def city
    (client_profile.delivery_city.strip.length > 1) ? client_profile.delivery_city : company.city
  end
end