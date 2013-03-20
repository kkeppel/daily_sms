require 'googlevoiceapi'
require 'google_drive'
require 'yaml'
require 'mail'


$LOAD_PATH << File.dirname(__FILE__)
APP_CONFIG = YAML::load_file("config.yml")


#Credentials
login = APP_CONFIG["google_login"]
pass =  APP_CONFIG["google_password"]
email_user = APP_CONFIG["email_user"]
email_pass = APP_CONFIG["email_pass"]

require 'models/init'

# Spreadsheet Setup
@session = GoogleDrive.login(login, pass)

# Google Voice Setup
@api = GoogleVoice::Api.new(login, pass)

# Mail Setup
options = { :address              => "smtp.gmail.com",
            :port                 => 587,
            :domain								=> "cater2.me",
            :user_name            => email_user,
            :password             => email_pass,
            :authentication       => 'plain',
            :enable_starttls_auto => true  }
            
Mail.defaults do
  delivery_method :smtp, options
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
		if order.order_proposal.selected == true
			puts "#{order.order_proposal.vendor.name} : #{order.order_for.strftime('%l:%M %p')}"
			new_spreadsheet.list.push({"Vendor Name" => order.order_proposal.vendor.name,
				"Client Name" => order.client.name,
				"Order For Time" => order.order_for.strftime('%l:%M %p'),
				"Text Number" => order.order_proposal.vendor.MorningText,
				"Status" => order.order_status_id == 2 ? "Canceled" : "Needs Confirmation"})
			new_spreadsheet.save()
		end
	end

	puts "YAY DONE! Let's send some texts!!"

	# test db connection
	vendors = DB[:vendors]
	row_data, clients, succeded, failed, current_row_number = [], [], [], [], 2
	# get array of numbers
	vendors.each do |vendor|
		row_data << [clean_numbers(vendor[:MorningText]), vendor[:name]] if vendor[:MorningText] != ""
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
			row_data << [@doc[row, 2] != "" ? clean_numbers(@doc[row, 2]) : clean_numbers(@doc[row, 6]), @doc[row, 3]]
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

def clean_numbers(number)
	number.gsub!(/\D/, '')
	"+1" + number
end
