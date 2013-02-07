class Client < Sequel::Model
	one_to_many :order_request
	many_to_one :company
end