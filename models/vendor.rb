class Vendor < Sequel::Model
	one_to_many :order_proposals, :conditions => {:selected => true}
	many_to_many :order_requests, :join_table=>:order_proposals,:left_key=>:vendor_id, :right_key=>:order_id
	many_to_many :orders_confirmed_for_today, :clone=>:order_requests, :conditions=>{Sequel.function(:DATE,:order_for)=>Date.today, :order_status_id=>4, 
		:order_proposals__selected => true}
	many_to_many :orders_canceled_for_today, :clone=>:order_requests, :conditions=>{Sequel.function(:DATE,:order_for)=>Date.today, :order_status_id=>2, 
		:order_proposals__selected => true}
	
	CALL_VENDORS = ["AK Subs","Anatolian Kitchen","Arabian Bites","Arki","Bamboo Asia","Beautifull","Bistro Mozart","Breaking Bread","Bun Mee","Cater2U","CreoLa Bistro","Crystal Springs Catering","Crouching Tiger Restaurant","DeLessio","Dino's","Golden Flower","Jeffrey's","Jenny's Churros","Macadamia Events & Catering","Mandalay","Mayo & Mustard","Missing Link","Nob Hill Pizza","Old World Food Truck","Opa","Patxi's Campbell","Patxi's Irving","Phat Thai","Purple Plant","Queen's","Santino's","Senor Sisig","Soup Freaks","Source","Spiedo","Tian Sing","Tomkat","Village Cheese House","We Sushi"]
	
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
			when 1 then message.push ". Please text back with the driver's number to confirm. Thanks!"
			else message.push ". Please text back with the number of the driver(s) to confirm. Thanks!"
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
