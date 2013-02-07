class Company < Sequel::Model
	one_to_one :client
end