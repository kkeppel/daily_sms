require 'googlevoiceapi'
require 'google_drive'
require 'sequel'
require 'yaml'
require 'mail'


$LOAD_PATH << File.dirname(__FILE__)


task :environment do
	location = ENV['location'] || 'SF'
	APP_CONFIG = YAML::load_file("config.yml")[location]
	@google_drive = GoogleDrive.login(APP_CONFIG["google"]["login"], APP_CONFIG["google"]["password"])
	@google_voice = GoogleVoice::Api.new(APP_CONFIG["google"]["login"], APP_CONFIG["google"]["password"])
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
	spreadsheet = @google_drive.spreadsheet_by_title("DailyOrdersTemplate").duplicate("Daily Order Confirmations #{Date.today.month}/#{Date.today.day}").worksheets[0]
	OrderRequest.for_today.eager_graph([{:order_proposal=>:vendor},{:client=>:company},:client_profile,:catering_extra_labels]).
	order(Sequel.qualify(:vendor,:name), :order_status_id, :order_for,Sequel.qualify(:order_proposal,:id_order_proposal)).all.each do |order|
		spreadsheet.list.push({
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
	spreadsheet.save
end

task :message_vendors_ny do
	puts "Creating the spreadsheet for today! this will take approximately forever...."
	master_sheet = @session.spreadsheet_by_title("Daily Order Confirmations Master")
	new_spreadsheet = master_sheet.duplicate("Daily Order Confirmations #{Date.today.month}/#{Date.today.day}")
	file = @session.file_by_title(new_spreadsheet.title)
	file.acl.push(scope_type: "user", scope: "kathy@cater2.me", role: "writer")
	file.acl.push(scope_type: "user", scope: "alex@cater2.me", role: "writer")
	file.acl.push(scope_type: "user", scope: "david@cater2.me", role: "writer")
	file.acl.push(scope_type: "user", scope: "kevin@cater2.me", role: "writer")
	new_spreadsheet = new_spreadsheet.worksheets[0]

	orders_for_today = OrderRequest.where("order_for LIKE '#{Date.today} %'")
	orders_for_today.each do |order|
		puts "#{order.order_proposal.vendor.name} : #{order.order_for.strftime('%l:%M %p')}"
		new_spreadsheet.list.push({"Vendor Name" => order.order_proposal.vendor.name,
			"Client Name" => order.client.name,
			"Order For Time" => order.order_for.strftime('%l:%M %p'),
			"Text Number" => order.order_proposal.vendor.MorningText,
			"Status" => order.order_status_id == 2 ? "Canceled" : "Call them bitches"})
		new_spreadsheet.save()
	end

	puts "YAY DONE! Let's send some texts!!"

	# test db connection
	vendors = Vendor.all
	row_data, clients, succeded, failed, current_row_number = [], [], [], [], 2
	# get array of numbers
	vendors.each do |vendor|
		row_data << [vendor.clean_numbers(vendor[:MorningText]), vendor[:name]] if vendor[:MorningText] != ""
	end

	row_data.each do |r|
		number = r[0]
		vendor_name = r[1]
		message = Vendor.where(name: vendor_name).first.get_message

    # use google voice to send sms
		status = @api.sms(number, message)
		if status.code.to_i == 200
    	succeded << "#{number} : #{message}"
    	puts "	Texted #{vendor_name} at #{number} with message: #{message}\n"
			for row in 2..new_spreadsheet.num_rows
				new_spreadsheet[row, 5] = "Awaiting Response" if new_spreadsheet[row, 1] == vendor_name
	      new_spreadsheet.save()
			end
    else
    	failed << "#{number} : #{message}"
    end
	end
	subject = "Text Confirmations Status for #{Date.today} Send #{succeded.count}; Failed: #{failed.count}"
	content = ["Succeeded:",succeded.join("\r\n"),"Failed:", failed.join("\r\n")].join("\n")
	deliver_text_status(subject, content, login)

	puts "Check out your fancy new spreadsheet!!"
end

task :message_vendors_sf do
	@doc = @session.spreadsheet_by_title("Daily Order Confirmations #{Date.today.month}/#{Date.today.day}").worksheets[0]
	row_data, succeded, failed = [], [], []
	
	# get array of all numbers and vendor names
	for row in 2..@doc.num_rows
		if @doc[row,1].downcase.match(/text/) #TODO: Change to text
			row_data << [@doc[row, 2] != "" ? Vendor.clean_numbers(@doc[row, 2]) : clean_numbers(@doc[row, 6]), @doc[row, 3]]
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
		#write "Awaiting Response" into Status column in @doc if sms is successful
		for row in 2..@doc.num_rows
			@doc[row, 1] = "Awaiting Response" if clean_numbers(@doc[row, 2]) == number or clean_numbers(@doc[row, 6]) == number
      @doc.save()
		end
	end

	subject = "Text Confirmations Status for #{Date.today} Send #{succeded.count}; Failed: #{failed.count}"
	content = ["Succeeded:",succeded.join("\r\n"),"Failed:", failed.join("\r\n")].join("\n")
	deliver_text_status(subject, content, login)
end

def deliver_text_status(subject, content, login)
	Mail.deliver do
	  # to 'yuriy@cater2.me'
	  to 'kathy@cater2.me'
	  from login
	  subject subject
	  body content
	end
end
