class OrderProposalItem < Sequel::Model
	many_to_one :order_proposal
	many_to_one :vendor_item
end