class OrderRequest < Sequel::Model
	one_to_one :order_proposal, :key=> :order_id
	many_to_one :client
	one_to_many :catering_extras
	def self.confirmations
		self.find_by_sql("SELECT vendors.name AS vendor,
				order_proposals.vendor_id,
				order_requests.id_order AS 'o_id',
				DATE_FORMAT( order_requests.order_for, '%l:%i %p') AS 'order_time',
				companies.name AS 'client',
				order_requests.last_updates AS 'notes',
				order_requests.order_status_id as 'status'

			FROM order_requests, order_proposals, companies, clients, vendors

			WHERE order_requests.id_order = order_proposals.order_id
				AND order_requests.client_id = clients.id_client
				AND clients.company_id = companies.id_company
				AND order_proposals.vendor_id = vendors.id_vendor
				AND order_proposals.vendor_id = '#{vendor.id}'
				AND DATE( order_requests.order_for ) = '#{Date.today}'
				AND order_proposals.selected = 1
				AND order_requests.order_status_id = 4

			ORDER BY vendor_id, order_for")
	end

	def self.cancelations
		find_by_sql("SELECT vendors.name AS vendor,
				order_proposals.vendor_id,
				order_requests.id_order AS 'o_id',
				DATE_FORMAT( order_requests.order_for, '%l:%i %p') AS 'order_time',
				companies.name AS 'client',
				order_requests.last_updates AS 'notes',
				order_requests.order_status_id as 'status'

			FROM order_requests, order_proposals, companies, clients, vendors

			WHERE order_requests.id_order = order_proposals.order_id
				AND order_requests.client_id = clients.id_client
				AND clients.company_id = companies.id_company
				AND order_proposals.vendor_id = vendors.id_vendor
				AND order_proposals.vendor_id = '#{vendor.id}'
				AND DATE( order_requests.order_for ) = '#{Date.today}'
				AND order_proposals.selected = 1
				AND order_requests.order_status_id = 2

			ORDER BY vendor_id, order_for")
	end
end