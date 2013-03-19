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
# @doc = @session.spreadsheet_by_title("Daily Order Confirmations #{Date.today.month}/#{Date.today.day}").worksheets[0]

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

task :test_spreadsheet_creation do
	# create spreadsheet for today
	new_spreadsheet = @session.create_spreadsheet("Daily Order Confirmations #{Date.today.month}/#{Date.today.day}")
	file = @session.file_by_title(new_spreadsheet.title)
	file.acl.push(scope_type: "user", scope: "kathykeppel@gmail.com", role: "writer")
	new_spreadsheet = new_spreadsheet.worksheets[0]
	new_spreadsheet[1, 1] = "Vendor Name"
	new_spreadsheet[1, 2] = "Text Number"
	new_spreadsheet[1, 3] = "Order for Time"
	new_spreadsheet[1, 4] = "Client Name"
	new_spreadsheet[1, 5] = "Status"
	new_spreadsheet.save()
end

task :message_vendors do
	row_data = []
	succeded = []
	failed = []

	

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
			if clean_numbers(@doc[row, 2]) == r[0] or clean_numbers(@doc[row, 6]) == r[0]
				@doc[row, 1] = "Awaiting Response"
      end
      @doc.save()
		end
	end
	subject = "Text Confirmations Status for #{Date.today} Send #{succeded.count}; Failed: #{failed.count}"
	content = ["Succeeded:",succeded.join("\r\n"),"Failed:", failed.join("\r\n")].join("\n")

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
