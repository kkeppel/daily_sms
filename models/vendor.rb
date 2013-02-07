class Vendor < Sequel::Model
	one_to_many :order_proposals
	many_to_many :order_requests, :join_table=>:order_proposals,:left_key=>:vendor_id, :right_key=>:order_id

	def get_message
		message = ""
		confirmations = OrderRequest.confirmations(id)
		cancellations = OrderRequest.cancellations(id)

		if confirmations.empty?
			message += "No orders to confirm today. Please text back to confirm. Thanks!"
		elsif confirmations.length == 1
			message += "1 order for today"
			# order information
			message += "; " + confirmations[0].order_time + " for " + confirmations[0].client
			# add extra information
			order_id = confirmations[0].o_id
			extras = CateringExtra.get_extras(order_id)
			message += add_extras_to_message(extras, notes)
			# cancellations
			message += add_cancellations(cancellations)
			# confirmation number
			message += ". Please text back with the driver's number to confirm. Thanks!"
		else
			message += confirmations.length + " orders for today"
			confirmations.each do |c|
				# order information
				message += "; " + c.order_time + " for " + c.client
				# add extra information for this order
				order_id = c.o_id
				extras = CateringExtra.get_extras(order_id)
				message += add_extras_to_message(extras, notes)
			end
			# cancellations
			message += add_cancellations(cancellations)
			# confirmation number
			message += ". Please text back with the number of the driver(s) to confirm. Thanks!"
		end
		message
	end

	def add_extras_to_message(extras, notes)
		add_to_message = ""
		if extras.length == 1
			add_to_message += ", w/utensils"
		elsif extras.length == 2
			add_to_message += ", w/utensils+paper ware"
		end
		unless notes.nil?
			add_to_message += " (" + notes + ")"
		end
		add_to_message
	end

	def add_cancellations(cancellations)
		add_to_message = ""
		if cancellations
			cancellations.each do |can|
				add_to_message += ". " + can.order_time + " for " + can.client + "was CANCELLED"
			end
		end
		add_to_message
	end

end