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
		vendor = Vendor.where(name: vendor_name)
		confirmations = OrderRequest.confirmations
		cancellations = OrderRequest.cancellations

		# correct grammar for number of confirmed orders]
		if confirmations.empty?
			message += "No orders to confirm today"
		elsif confirmations.length == 1
			message += "1 order for today"
			message += "; " + confirmations[0].order_time + " for " + confirmations[0].client
			order_id = confirmations[0].o_id
			extras = CateringExtra.find_by_sql("SELECT client_profile_id,
							order_request_id,
							extra_label_id
						FROM catering_extra
						WHERE order_request_id = '#{order_id}'
							AND (extra_label_id = 3 OR extra_label_id = 2)")
			if extras.length == 1
				message += ", w/utensils"
			elsif extras.length == 2
				message += ", w/utensils+paper ware"
			end
			unless confirmations[0].notes.nil?
				message += " (" + confirmations[0].notes + ")"
			end
		else
			message += confirmations.length + " orders for today"
			confirmations.each do |c|
				order_id = c.o_id
				extras = CateringExtra.find_by_sql("SELECT client_profile_id,
							order_request_id,
							extra_label_id
						FROM catering_extra
						WHERE order_request_id = '#{order_id}'
							AND (extra_label_id = 3 OR extra_label_id = 2)")
				message += "; " + c.order_time + " for " + c.client
				if extras.length == 1
					message += ", w/utensils"
				elsif extras.length == 2
					message += ", w/utensils+paper ware"
				end
				unless c.notes.nil?
					message += " (" + c.notes + ")"
				end
			end
		end

		# print cancellations if they exist
		if cancellations
			cancellations.each do |can|
				message += ". " + can.order_time + " for " + can.client + "was CANCELLED"
			end
		end

		# confirmation code depends on how many orders we have
		if confirmations.empty?
			message += ". Please text back to confirm. Thanks!"
		elsif confirmations.length == 1
			message += ". Please text back with the driver's number to confirm. Thanks!"
		else
			message += ". Please text back with the number of the driver(s) to confirm. Thanks!"
		end

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
