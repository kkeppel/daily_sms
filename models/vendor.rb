class Vendor < Sequel::Model
	one_to_many :order_proposals, :conditions => {:selected => true}
	many_to_many :order_requests, :join_table=>:order_proposals,:left_key=>:vendor_id, :right_key=>:order_id
	many_to_many :orders_confirmed_for_today, :clone=>:order_requests, :conditions=>{Sequel.function(:DATE,:order_for)=>Date.today, :order_status_id=>4, 
		:order_proposals__selected => true}
	many_to_many :orders_canceled_for_today, :clone=>:order_requests, :conditions=>{Sequel.function(:DATE,:order_for)=>Date.today, :order_status_id=>2, 
		:order_proposals__selected => true}
	
	sf_call_vendors = ["AK Subs","Anatolian Kitchen","Arabian Bites","Arki","Bamboo Asia","Beautifull","Bistro Mozart","Breaking Bread","Bun Mee","Cater2U","CreoLa Bistro","Crystal Springs Catering","DeLessio","Dino's","Golden Flower","Jeffrey's","Jenny's Churros","Macadamia Events & Catering","Mandalay","Mayo & Mustard","Missing Link","Nob Hill Pizza","Old World Food Truck","Opa","Patxi's Campbell","Patxi's Irving","Phat Thai","Purple Plant","Queen's","Santino's","Senor Sisig","Soup Freaks","Source","Spiedo","Tian Sing","Tomkat","Village Cheese House","We Sushi"]
	ny_call_vendors = ["!Savory", "Anthi's", "Atlas Cafe", "Bagel and Bean", "Bagelworks", "Bian Dang", "BiBiFresh", "Bistro Caterers", "Bleeker Street Pizza", "Bourbon Street", "Brooklyn Mac", "Brooklyn Oyster Party", "Butcher Bar", "Carl's Steaks", "Cater2.me NYC", "Cayenne Catering", "Chola", "City Sandwich", "Clamenza's", "Crisp", "Dinosaur Bar-B-Que", "Eatery", "Favela Cubana", "FOODfreaks", "Galli", "Glaze Teriyaki Grill", "Graham Avenue Deli", "Indian Creperie", "Jing", "Jing Sushi", "Junko's Kitchen", "Just Salad", "Kashkaval", "Korilla BBQ", "kosofresh", "La Bella Torte", "La Casa de Camba", "La Lucha", "Lagniappe Doughnuts", "Lamazou Cheese", "Landhaus", "Local Cafe", "Lorimer Market", "Mark", "Mayhem and Stout", "Mimi and Coco", "Miss Elisabeth's", "Moustache", "Mrs. Dorsey's Kitchen", "Nucha's", "Palenque", "Peter's Since 1969", "Pita Pan", "Ponty Bistro", "Previti", "Rafaella", "Reena's Treats", "Robicelli's", "S'more Bakery", "Sao Mai", "Shalom Bombay", "Solber Pupusas", "Sushi Shop", "Teany", "The Counter", "Tuch Shop", "Turco Mediterranean", "Tuscany Catering", "Uncle Moe's", "Valducci's Pizza", "Via Emilia", "Wafels and Dinges", "Waffle and Wolf", "WaffleWich Way", "Yushi Asian Kitchen", "Zizi Limona"]
	
	CALL_VENDORS = ENV['location'] == 'NY' ? ny_call_vendors : sf_call_vendors
	
	def get_message
		message = []
		if orders_confirmed_for_today.empty?
			message.push  "No orders to confirm today"
		else
			message.push "#{pluralize(orders_confirmed_for_today.count,'order','orders')} for today"
			orders_confirmed_for_today.each do |order|
				message.push "; #{order.order_time} for #{order.client.name}"
				case order.catering_extras.map{|extra| extra if [2,3].include?(extra.extra_label_id)}.compact.count
					when 1 then message.push ", w/utensils"
					when 2 then message.push ", w/utensils+paper ware"
				end
				if order.notes
					message.push " (#{order.notes})"
				end
			end
		end
		orders_canceled_for_today.each do |order|
			message.push ". #{order.order_time} for #{order.client.name} was CANCELLED"
		end
		case orders_confirmed_for_today.count
			when 0 then message.push ". Please text back to confirm. Thanks!"
			when 1 then message.push ". Please confirm. If not you, text back with the number of the driver to confirm. Thanks!"
			else message.push ". Please confirm. If not you, text back with the number of the driver(s) to confirm. Thanks!"
		end
		message.join("")
	end

	
	def pluralize(count, singular, plural = nil)
    "#{count || 0} " + ((count == 1 || count =~ /^1(\.0+)?$/) ? singular : (plural || singular.pluralize))
  end

  def self.clean_numbers(number)
		number.gsub!(/\D/, '')
		"+1" + number
	end

	def notification_preference
		if CALL_VENDORS.include?(self.name)
			"To Call"
		else
			"To Text"
		end
	end
end
