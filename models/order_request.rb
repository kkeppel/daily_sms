class OrderRequest < Sequel::Model
	one_to_one :order_proposal, :key=> :order_id
	many_to_one :client
	one_to_many :catering_extras

	def self.confirmations(vendor_id)
		self.find_by_sql("SELECT vendors.*,
				order_proposals.*,
				order_requests.id_order AS 'o_id',
				DATE_FORMAT( order_requests.order_for, '%l:%i %p') AS 'order_time',
				companies.name AS 'client',
				order_requests.last_updates AS 'notes'

			FROM order_requests, order_proposals, companies, clients, vendors

			WHERE order_requests.id_order = order_proposals.order_id
				AND order_requests.client_id = clients.id_client
				AND clients.company_id = companies.id_company
				AND order_proposals.vendor_id = vendors.id_vendor
				AND order_proposals.vendor_id = '#{vendor_id}'
				AND DATE( order_requests.order_for ) = '#{Date.today}'
				AND order_proposals.selected = 1
				AND order_requests.order_status_id = 4")
	end

	def self.cancellations(vendor_id)
		find_by_sql("SELECT vendors.*,
				order_proposals.*,
				order_requests.id_order AS 'o_id',
				order_requests.last_updates AS 'notes',
				DATE_FORMAT( order_requests.order_for, '%l:%i %p') AS 'order_time',
				companies.name AS 'client',

			FROM order_requests, order_proposals, companies, clients, vendors

			WHERE order_requests.id_order = order_proposals.order_id
				AND order_requests.client_id = clients.id_client
				AND clients.company_id = companies.id_company
				AND order_proposals.vendor_id = vendors.id_vendor
				AND order_proposals.vendor_id = '#{vendor_id}'
				AND DATE( order_requests.order_for ) = '#{Date.today}'
				AND order_proposals.selected = 1
				AND order_requests.order_status_id = 2")
	end
end