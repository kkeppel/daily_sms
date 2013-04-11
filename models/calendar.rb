class Calendar < Sequel::Model
	one_to_one :company, :primary_key=>:company_id, :key => :id_company
  one_to_many :clients, :primary_key => :company_id,:key=>:company_id
end