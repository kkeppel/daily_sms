class VendorItem < Sequel::Model
	one_to_many :food_categories
	one_to_many :order_proposal_items

	def food_category_label(item)
		food_category = FoodCategory.where(id_food_category: item.food_category_id).first
		food_category.label
	end
end