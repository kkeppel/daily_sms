require 'twilio-ruby'
require 'google_drive'

APP_CONFIG = YAML::load_file("config.yml")

# Google Drive credentials
session = GoogleDrive.login(APP_CONFIG["google_login"], APP_CONFIG["google_password"])
@doc = session.spreadsheet_by_title("Daily Orders Sheet (safe)").worksheets[0]

# Twilio credentials
account_sid = APP_CONFIG["twilio_sid"]
auth_token = APP_CONFIG["twilio_auth_token"]
@client = Twilio::REST::Client.new account_sid, auth_token

task :message_vendors do

	for row in 2..@doc.num_rows
		# get contact number
		number = @doc[row, 2] != "" ? clean_numbers(@doc[row, 2]) : clean_numbers(@doc[row, 6])
		p @doc[row, 2] != "" ? clean_numbers(@doc[row, 2]) : clean_numbers(@doc[row, 6])

		# use twilio to send sms, :to => number, :from => google_voice_number, :message => message
		@client.account.sms.messages.create(
			from: ,
		  to: number,
		  body: 'Oh hey!'
		)

		# write "Awaiting Response" into Status column in @doc if sms is successful
		@doc[row, 4] = "Awaiting Response"
		@doc.save()

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

