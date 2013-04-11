class FoodCategory < Sequel::Model
	many_to_one :vendor_item
end