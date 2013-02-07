class OrderRequest < Sequel::Model
	one_to_one :order_proposal, :key=> :order_id
	many_to_one :client
	one_to_many :catering_extras

	dataset_module do
		def active
			where{last_updated > Date.today-14}
		end
	end

	set_dataset(self.active)

	def arrival_time
		increment_by = client.client_profile.profile_delivery_diff=="Easy" ? 15*60 : 25*60
		(order_time-increment_by).strftime("%H:%M %P")
	end
	def order_date
		order_time.strftime("%A %B %d %Y")
	end
	def setup_time
		order_time.strftime("%H:%M %P")
	end
	def order_time
		Time.parse("#{order_for}#{TIMEZONE}")
	end
	def delivery_instructions
		client.delivery_instructions
	end
	def delivery_address
		client.company.address ? client.company.full_address : client.client_profile.full_address
	end
	def serving_instructions
		instruction = order_proposal.try(:serving_instructions) || []
		instruction.collect(&:label)
	end
	def difficulty
		client.client_profile.profile_delivery_diff
	end
	def status
		case order_status_id
			when 4 then "confirmed"
			when 7 then "canceled"
			else order_status_id
		end
	end
	def delivery_status
		order_deliveries.last || OrderDelivery.new
	end
end