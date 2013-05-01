class Event

	def initialize
		@srv = GoogleCalendar::Service.new(APP_CONFIG["calendar"]["login"], APP_CONFIG["calendar"]["password"])
	end

	def self.create_events_for_client(calendar, order)
		sf_order_for = order.order_for.to_time + (60*60*3)
		order = OrderRequest.where(id_order: 35381).first
		get_event_description(order)
		event = calendar.create_event
		event.title =  order.order_proposal.vendor.public_name
		if ENV['location'] == "SF"
			one_hour = sf_order_for + (60*60)
			event.st = order.order_for.to_time + (60*60*3)	
		else
			one_hour = order.order_for.to_time + (60*60)
			event.st = order.order_for.to_time
		end
		# event.en = one_hour
		event.desc = @description
		event.save!
	end

	def self.get_event_description(order)
		last_category = "-"
		@description = "<a href='http://cater2.me/dashboard/feedback/?oid=" + order.id_order.to_s + "'>" + order.order_proposal.vendor.public_name + " Feedback</a>\n"
		@description += "<input type='hidden' id='order_id' value='#{order.id_order}'></input>"
		items = order.order_proposal.order_proposal_items
		for cat_id in 1..20
			items.each do |item|	
				if item.vendor_item.food_category_id == cat_id
					@description += "<input type='hidden' id='vendor_item_id' value='#{item.vendor_item.id_vendor_item}'></input>"
					item.vendor_item.vegetarian ? veg = '*' : veg = ''
					item.vendor_item.gluten_safe ? glu = '(G)' : glu = ''
					item.vendor_item.dairy_safe ? dai = '(D)' : dai = ''
					(item.vendor_item.vegetarian && item.vendor_item.dairy_safe && item.vendor_item.egg_safe) ? vegan = '*' : vegan = ''
					item.vendor_item.nut_safe ? nut = '(N)' : nut = ''
					item.vendor_item.egg_safe ? egg_safe = '(E)'	: egg_safe = ''
					item.vendor_item.soy_safe ? soy = '(S)' : soy = ''
					item.vendor_item.contains_honey ? hon = '(Contains honey)' : hon = ''
					item.vendor_item.contains_shellfish ? she = '(Contains shellfish)' : she = ''
					item.vendor_item.contains_alcohol ? alc = '(Contains alcohol)' : alc = ''

					if last_category != item.vendor_item.food_category_label(item.vendor_item)			
						@description +=  "\n<b>" + item.vendor_item.food_category_label(item.vendor_item) + "</b>\n"
						last_category = item.vendor_item.food_category_label(item.vendor_item)
					end
					temp = ""
					temp += item.vendor_item.description ? (': ' + item.vendor_item.description) : ''
					temp += item.notes != "" ? (' (' + item.notes + ')') : ''
					@description += '* ' 
					@description += item.vendor_item.menu_name
					@description += veg
					@description += vegan
					@description += temp
					@description += " <font size='1' color='#990066'>"
					@description += " "
					@description += glu
					@description += dai
					@description += nut
					@description += egg_safe
					@description += soy
					@description += hon
					@description += she
					@description += alc
					@description += "</font>\n"	
					@description += "<input type='hidden' name='end_item'></input>"
				end
			end
		end
		legend = "\n"+'<b>Allergen Key:</b> *Vegetarian, **Vegan, (G) Gluten Safe, (D) Dairy Safe, (N) Nut Safe, (E) Egg Safe, (S) Soy Safe.' + "\n" +'Items have been prepared in facilities that may contain trace amounts of common allergens. See below for full disclaimer.'
		@description += legend
	end
end