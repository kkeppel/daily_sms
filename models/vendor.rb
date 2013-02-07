class Vendor < Sequel::Model
	one_to_many :order_proposals
	many_to_many :order_requests, :join_table=>:order_proposals,:left_key=>:vendor_id, :right_key=>:order_id
end