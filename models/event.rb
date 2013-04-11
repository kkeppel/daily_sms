class Event

	def initialize
		@srv = GoogleCalendar::Service.new(APP_CONFIG["calendar"]["login"], APP_CONFIG["calendar"]["password"])
	end

	def self.query_events(events, calendar)
		events.is_a?(Array) ? events.each { |event| update_event(event, calendar, array=true) } : update_event(events, calendar, array=false)
	end

	def self.update_event(event, calendar, array=false)
		event_for = event.st.to_time
		event_vendor_id = Vendor.where(public_name: event.title).first.id_vendor
		order = get_order_for_event(event).first
		order.order_proposals.each do |prop|
			order_vendor_id = prop.vendor_id
			unless order_vendor_id == event_vendor_id
				puts "VENDOR CHANGED!!!!!"
				delete_and_recreate_event(order, event, calendar)
			end
		end
		unless order.order_for == event_for
			puts "TIME CHANGED!!!"
			delete_and_recreate_event(order, event, calendar)
		end

		check_items(order, event, calendar)
	end

	def self.get_order_for_event(event)
		oid1 = event.desc.split("id='order_id' value='")[1]
		order_id = oid1.split("'")[0]
		OrderRequest.where(id_order: order_id)
	end

	def self.delete_and_recreate_event(order, event, calendar)
		event.destroy!
		create_events_for_client(calendar, order)
	end

	def self.create_events_for_client(calendar, order)
		get_event_description(order)
		one_hour = order.order_for.to_time + (60*60)
		event = calendar.create_event
		event.title =  order.order_proposals[0].vendor.public_name
		event.st = order.order_for
		event.en = one_hour
		event.desc = @description
		event.save!
	end

	def self.get_event_description(order)
		order.order_proposals.each do |prop|
			items = 
				VendorItem.join(order_proposal_items: :vendor_item_id).join(food_categories: :food_category_id)
				.where("id_food_category = food_category_id
							   AND id_vendor_item = vendor_item_id
							   	AND list_order < 19
							   AND order_proposal_id = '"+prop.id_order_proposal.to_s + "'")
			last_category = "-"
			@description = "<a href='http://cater2.me/dashboard/feedback/?oid=" + order.id_order.to_s + "'>" + prop.vendor.public_name + " Feedback</a>\n"
			@description += "<input type='hidden' id='order_id' value='#{order.id_order}'></input>"
			items.each do |item|
				@description += "<input type='hidden' id='vendor_item_id' value='#{item.id_vendor_item}'></input>"

				item.vegetarian ? veg = '*' : veg = ''
				item.gluten_safe ? glu = '(G)' : glu = ''
				item.dairy_safe ? dai = '(D)' : dai = ''
				(item.vegetarian && item.dairy_safe && item.egg_safe) ? vegan = '*' : vegan = ''
				item.nut_safe ? nut = '(N)' : nut = ''
				item.egg_safe ? egg_safe = '(E)'	: egg_safe = ''
				item.soy_safe ? soy = '(S)' : soy = ''
				item.contains_honey ? hon = '(Contains honey)' : hon = ''
				item.contains_shellfish ? she = '(Contains shellfish)' : she = ''
				item.contains_alcohol ? alc = '(Contains alcohol)' : alc = ''
				
				if last_category != item.food_category_label(item)
					@description += "\n<b>" + item.food_category_label(item) + "</b>\n"
					last_category = item.food_category_label(item)
				end

				temp = ""
				temp += item.description ? (': ' + item.description) : ''
				temp += item.notes ? (' (' + item.notes + ')') : ''

				@description += '* ' 
				@description += item.menu_name
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
			legend = "\n"+'<b>Allergen Key:</b> *Vegetarian, **Vegan, (G) Gluten Safe, (D) Dairy Safe, (N) Nut Safe, (E) Egg Safe, (S) Soy Safe.' + "\n" +'Items have been prepared in facilities that may contain trace amounts of common allergens. See below for full disclaimer.'
			@description += legend
		end
	end

	def self.check_items(order, event, calendar)
		event_vendor = event.title
		event_item_descriptions, previous_item_cat, item_vegan, order_vegan = [], "", false, false
		event.desc.scan(/vendor_item_id' value='(.*?)ont>\n/m){|x| event_item_descriptions << x}
		event_item_descriptions.each do |this_item|
			item_id = this_item[0].split("'")[0].to_i
			cat = this_item[0].match(/<b>(.*?)b>/m).to_s.gsub("<b>","").gsub("</b>","").strip
			cat = cat == "" ? previous_item_cat : cat
			cat_id = FoodCategory.where(label: cat).first.id_food_category
			item_name = this_item[0].match(/\* (.*?)(\s|\S):/m).to_s.gsub("*","").gsub(":","").strip
			veg_check = this_item[0].match(/\* (.*?)(\s|\S):/m).to_s.gsub("* ","").gsub(":","")
			item_description = this_item[0].match(/\: (.*?) \(/m).to_s.gsub(": ","").gsub(" (","").strip
			item_veg = veg_check.include?("*")
			item_glu = this_item[0].include?("(G)")
			item_dai = this_item[0].include?("(D)")
			item_nut = this_item[0].include?("(N)")
			item_egg = this_item[0].include?("(E)")
			item_soy = this_item[0].include?("(S)")
			item_hon = this_item[0].include?("(Contains honey)")
			item_she = this_item[0].include?("(Contains shellfish)")
			item_alc = this_item[0].include?("(Contains alcohol)")
			item_vegan = true if (item_veg && item_dai && item_egg)

			order_item = VendorItem.where(id_vendor_item: item_id).first
			order_vegan = true if (order_item.vegetarian && order_item.dairy_safe && order_item.egg_safe)
			if order_item.nil? || item_name != order_item.menu_name || item_description != order_item.description || item_glu != order_item.gluten_safe || item_dai != order_item.dairy_safe || item_nut != order_item.nut_safe || item_egg != order_item.egg_safe || item_soy != order_item.soy_safe || item_hon != order_item.contains_honey || item_she != order_item.contains_shellfish || item_alc != order_item.contains_alcohol || cat_id != order_item.food_category_id || item_veg != order_item.vegetarian || item_vegan != order_vegan
				puts "ITEM CHANGED!!!!"
				delete_and_recreate_event(order, event, calendar)
			end
			previous_item_cat = cat unless cat == ""
		end
	end

end