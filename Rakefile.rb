require 'twilio-ruby'
require 'google_drive'

APP_CONFIG = YAML::load_file("config.yml")

# Google Drive credentials
session = GoogleDrive.login(APP_CONFIG["google_login"], APP_CONFIG["google_password"])
@doc = session.spreadsheet_by_title(APP_CONFIG["spreadsheet_title"]).worksheets[0]

# Twilio credentials
account_sid = APP_CONFIG["twilio_sid"]
auth_token = APP_CONFIG["twilio_auth_token"]
@client = Twilio::REST::Client.new account_sid, auth_token

task :message_vendors do
	message = ""
	row_data = []
	# get array of all numbers and vendor names
	for row in 2..@doc.num_rows
		row_data << [@doc[row, 2] != "" ? clean_numbers(@doc[row, 2]) : clean_numbers(@doc[row, 6]), @doc[row, 3]]
	end

	# make array unique by number
	row_data = row_data.uniq{ |r| r[0] }

	row_data.each do |r|
		number = r[0]
		vendor_name = r[1]
		message = Vendor.find_by_name(vendor_name).first.get_message

		# correct grammar for number of confirmed orders]


		# use twilio to send sms, :to => number, :from => google_voice_number, :message => message
		@client.account.sms.messages.create(
			from: APP_CONFIG["from_number"],
		  to: number,
		  body: message
		)

		# write "Awaiting Response" into Status column in @doc if sms is successful
		for row in 2..@doc.num_rows
			if @doc[row, 2] == r[0] || @doc[row, 6] == r[0]
				@doc[row, 4] = "Awaiting Response"
			end
		end
	end

end

task :reset_status_for_testing do

	for row in 2..@doc.num_rows
		@doc[row, 4] = "Confirmed"
		@doc.save()
	end

end


def clean_numbers(number)
	number.gsub!(/\D/, '')
	"+1" + number
end
