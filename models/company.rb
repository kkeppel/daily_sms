class Company < Sequel::Model
	one_to_many :clients
	one_to_one :calendar
end