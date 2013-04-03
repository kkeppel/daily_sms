require 'googlevoiceapi'
require 'google_drive'
require 'sequel'
require 'yaml'
require 'mail'


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

def send_mail(subject, content)
	Mail.deliver do
	  to 'yuriy@cater2.me'
	  from 'yuriy@cater2.me'
	  subject subject
	  body content
	end
end
