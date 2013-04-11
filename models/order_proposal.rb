class OrderProposal < Sequel::Model
  dataset_module do
    def confirmed
      filter(selected: true)
    end
  end
  set_dataset(self.confirmed)
  many_to_one :vendor
  one_to_one :order_request, :key=>:id_order
  one_to_many :order_proposal_items

end