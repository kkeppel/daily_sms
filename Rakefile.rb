require 'googlevoiceapi'
require 'google_drive'
require 'sequel'
require 'yaml'
require 'mail'
require 'gcalapi'


$LOAD_PATH << File.dirname(__FILE__)


task :environment do
	location = ENV['location'] || 'SF'
	@regenerate = ENV['regenerate'] || false
	APP_CONFIG = YAML::load_file("config.yml")[location]
	@google_drive = GoogleDrive.login(APP_CONFIG["google"]["login"], APP_CONFIG["google"]["password"])
	@google_voice = GoogleVoice::Api.new(APP_CONFIG["google"]["login"], APP_CONFIG["google"]["password"])
	@contributors = APP_CONFIG["contributors"]
	@worksheet_title = "Daily Order Confirmations #{Date.today.month}/#{Date.today.day}"
	DB = Sequel.connect(adapter: 'mysql2', 
											host: APP_CONFIG["db"]["host"],
											database: APP_CONFIG["db"]["database"], 
											user: APP_CONFIG["db"]["username"], 
											password: APP_CONFIG["db"]["password"])
	require 'models/init'
	Mail.defaults do
		delivery_method :smtp, {
			:address              => "smtp.gmail.com",
			:port                 => 587,
			:domain								=> "cater2.me",
			:user_name						=> APP_CONFIG["google"]["login"],
			:password							=> APP_CONFIG["google"]["password"],
			:authentication				=>'plain',
			:enable_starttls_auto => true 
		}
	end
end
task :create_spreadsheet => :environment do
	if @google_drive.file_by_title(@worksheet_title) && @regenerate == false
		puts  "nothing to do"
	else
		worksheet = @google_drive.spreadsheet_by_title("DailyOrdersTemplate").duplicate(@worksheet_title).worksheets[0]
		OrderRequest.for_today.eager_graph([{:order_proposal=>:vendor},{:client=>:company},:client_profile,:catering_extra_labels]).
		order(Sequel.qualify(:vendor,:name), :order_status_id, :order_for,Sequel.qualify(:order_proposal,:id_order_proposal)).all.each do |order|
			worksheet.list.push({
				"Completed" => order.order_proposal.vendor.MorningText.length>1 ? "To Text" : "To Call",
				"Primary Number" => order.order_proposal.vendor.MorningText,
				"VendorName" => order.order_proposal.vendor.name,
				"OrderStatus" => order.order_status_id == 2 ? "Canceled" : "Confirmed",
				"OrderForTime" => order.order_time,
				"PhoneNumber" => order.order_proposal.vendor.phone_number2,
				"tbl_Vendor Contact Info.PersonalNumber" => order.order_proposal.vendor.personal_number2,
				"CompanyName" => order.client.name,
				"ProposalNumber" => order.order_proposal.id_order_proposal,
				"UpdateTime" => order.update_time,
				"Update Notes" => order.update_notes,
	      "Contact"  => order.order_proposal.vendor.contact_first_name2,
	      "SecondaryContacts" => order.order_proposal.vendor.secondary_contacts2,
	      "SecondaryNumbers"  => order.order_proposal.vendor.secondary_numbers2,
	      "SecondaryNotes"    => order.order_proposal.vendor.secondary_notes2,
	      "Food allergies?"   => order.client.client_profile.food_allergies_cl,
				"Notes" => order.notes,
				"Utensils?" => order.catering_extra_labels.collect(&:label).include?("Utensils") ? "TRUE" : "FALSE",
				"Paper Ware?" => order.catering_extra_labels.collect(&:label).include?("Paper Ware") ? "TRUE" : "FALSE",
				"Beverages?" => order.catering_extra_labels.collect(&:label).include?("Beverages") ? "TRUE" : "FALSE",
				"Folding Tables?" => order.catering_extra_labels.collect(&:label).include?("Folding Tables") ? "TRUE" : "FALSE",
				"BuyerAddress" => order.delivery_address,
				"City" => order.delivery_city,
	 	    "tbl_BuyerContactInfo.PersonalNumber" => order.client.contacts_personal_number_cl
			})
		end
		worksheet.save
		@contributors.each do |email|
				@google_drive.file_by_title(worksheet.spreadsheet.title).
				acl.push(scope_type: "user", scope: email, role: "writer")
		end
	end
end

task :message_vendors => :create_spreadsheet do
	worksheet = @google_drive.spreadsheet_by_title(@worksheet_title).worksheets[0]
	row_data, succeded, failed = [], [], []
	# get array of all numbers and vendor names
	for row in 2..worksheet.num_rows
		if worksheet[row,1].downcase.match(/text/) #TODO: Change to text
			row_data << [worksheet[row, 2] != "" ? Vendor.clean_numbers(worksheet[row, 2]) : clean_numbers(worksheet[row, 6]), worksheet[row, 3]]
		end
	end

	# make array unique by number
	row_data = row_data.uniq{ |r| r[0] }

	row_data.each do |r|
		number = r[0]
		vendor_name = r[1]
		message = Vendor.where(name: vendor_name).first.get_message
    # use google voice to send sms
		status = @api.sms(number, message)
		if status.code.to_i == 200
    	succeded << "#{number} : #{message}"
    else
    	failed << "#{number} : #{message}"
    end

		for row in 2..worksheet.num_rows
			worksheet[row, 1] = "Awaiting Response" if Vendor.clean_numbers(worksheet[row, 2]) == number or Vendor.clean_numbers(worksheet[row, 6]) == number
      worksheet.save()
		end
	end

	subject = "Text Confirmations Status for #{Date.today} Send #{succeded.count}; Failed: #{failed.count}"
	content = ["Succeeded:",succeded.join("\r\n"),"Failed:", failed.join("\r\n")].join("\n")
	send_mail(subject, content)
end

task :sync_calendars => :environment do
	cal_db = Calendar.all # EVERYONE
	# cal_db = Calendar.where(company_id: 366).first # TEST
	# cal_db = Calendar.exclude(company_id: [11, 29, 364]).all # EVERYONE BUT WARBY, 10GEN, AND TEST
	cal_db.each do |cal|
		USERNAME = "calendarNY@cater2.me"
		PASSWORD = "156cater"
		@srv = GoogleCalendar::Service.new(USERNAME, PASSWORD)
		cal_id = "cater2.me_" + cal.gcal_id + "@group.calendar.google.com"
		# cal_id = "cater2.me_" + cal_db.gcal_id + "@group.calendar.google.com" # TEST
		@feed = "http://www.google.com/calendar/feeds/"+ cal_id + "/private/full"
		@calendar = GoogleCalendar::Calendar.new(@srv, @feed)
		cal.company.clients.each do |client|
		# cal_db.company.clients.each do |client| # TEST
			@client_id, @time_min, @time_max = client.id_client, Date.today, Time.now + (60*60*24*30)
			formatted_start_min = @time_min.strftime("%Y-%m-%dT%H:%M:%S")
    	formatted_start_max = @time_max.strftime("%Y-%m-%dT%H:%M:%S")
			events_for_next_month = events(@feed, {"start-min" => formatted_start_min, "start-max" => formatted_start_max})
			if events_for_next_month != []
				query_events(events_for_next_month)
			else
				orders = orders_for_next_month_for_client(@client_id)
				puts "ORDERS! #{orders}"
				orders.each do |order|				
					one_hour = order.order_for.to_time + (60*60)
					get_event_description(order)
					create_events_for_client(@calendar, order, one_hour)
				end
			end
		end
	end
end

def events(feed, conditions = {})
  ret = @srv.query(feed, conditions)
  raise InvalidCalendarURL unless ret.code == "200"
  REXML::Document.new(ret.body).root.elements.each("entry"){}.map do |elem|
    elem.attributes["xmlns:gCal"] = "http://schemas.google.com/gCal/2005"
    elem.attributes["xmlns:gd"] = "http://schemas.google.com/g/2005"
    elem.attributes["xmlns"] = "http://www.w3.org/2005/Atom"
    entry = GoogleCalendar::Event.new
    entry.srv = @srv
    entry.load_xml("<?xml version='1.0' encoding='UTF-8'?>#{elem.to_s}")
  end
end

def query_events(events)
	events.is_a?(Array) ? events.each { |event| update_event(event, array=true) } : update_event(events, array=false)
end

def update_event(event, array=false)
	event_for = event.st.to_time
	event_vendor_id = Vendor.where(public_name: event.title).first.id_vendor
	@order = get_order_for_event(event).first
	@order.order_proposals.each do |prop|
		order_vendor_id = prop.vendor_id
		unless order_vendor_id == event_vendor_id
			puts "VENDOR CHANGED!!!!!"
			update_vendor(@order, event)
		end
	end

	unless @order.order_for == event_for
		puts "TIME CHANGED!!!"
		delete_event_and_update_time(@order, event)
	end

	check_items(event)
end

def get_order_for_event(event)
	oid1 = event.desc.split("id='order_id' value='")[1]
	order_id = oid1.split("'")[0]
	OrderRequest.where(id_order: order_id)
end

def check_items(event)
	event_vendor = event.title
	event_items, event_item_ids, event_item_descriptions, previous_item_cat, item_vegan, order_vegan = [], [], [], "", false, false
	event.desc.scan(/vendor_item_id' value='(.*?)ont>\n/m){|x| event_item_descriptions << x}
	event.desc.scan(/vendor_item_id' value='+\d{3,4}/){|x| event_items << x }
	event_items.each { |e| e.scan(/\d{3,4}/) { |n| event_item_ids << n.to_i}}
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
		puts "VEG! #{order_vegan}"
		if item_name != order_item.menu_name || item_description != order_item.description || item_glu != order_item.gluten_safe || item_dai != order_item.dairy_safe || item_nut != order_item.nut_safe || item_egg != order_item.egg_safe || item_soy != order_item.soy_safe || item_hon != order_item.contains_honey || item_she != order_item.contains_shellfish || item_alc != order_item.contains_alcohol || cat_id != order_item.food_category_id || item_veg != order_item.vegetarian || item_vegan != order_vegan
			puts "ITEM CHANGED!!!!"
			get_event_description(@order)
			delete_event_and_update_time(@order, event)
		end
		previous_item_cat = cat unless cat == ""
	end
end

def update_vendor(order, event)
	new_vendor = order.order_proposals[0].vendor.name
	one_hour = order.order_for.to_time + (60*60)
	event.destroy!
	event = @calendar.create_event
	event.title = order.order_proposal.vendor.name
	event.st = order.order_for
	event.en = one_hour
	event.desc = @description
	event.save!
end

def delete_event_and_update_time(order, event)
	one_hour = order.order_for.to_time + (60*60)
	puts "DONE!"
	event.destroy!
	event = @calendar.create_event
	event.title = order.order_proposals[0].vendor.name
	event.st = order.order_for
	event.en = one_hour
	event.desc = @description
	event.save!
end

def orders_for_next_month_for_client(client)
	time_min = Date.today
  time_max = Time.now + (60*60*24*30)
  OrderRequest.where("order_for BETWEEN ? and ?", time_min, time_max).where(client_id: client).all
end

def get_event_description(order)
	order.order_proposals.each do |prop|
		@order_vendor_name = prop.vendor.public_name
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
			@description += "<input type='hidden' id='vendor_item_id' value='#{item.id_vendor_item}'>start_item</input>"

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
			
			@description += "<input type='hidden'>end_item</input>"
		end
		legend = "\n"+'<b>Allergen Key:</b> *Vegetarian, **Vegan, (G) Gluten Safe, (D) Dairy Safe, (N) Nut Safe, (E) Egg Safe, (S) Soy Safe.' + "\n" +'Items have been prepared in facilities that may contain trace amounts of common allergens. See below for full disclaimer.'
		@description += legend
	end
end

def create_events_for_client(cal, order, one_hour)
	event = cal.create_event
	event.title =  @order_vendor_name
	event.st = order.order_for
	event.en = one_hour
	event.desc = @description
	event.save!
end

def send_mail(subject, content)
	Mail.deliver do
	  # to 'yuriy@cater2.me'
	  to 'kathy@cater2.me'
	  from 'kathy@cater2.me'
	  subject subject
	  body content
	end
end
