class OrderRequest < Sequel::Model
  one_to_one :order_proposal, :key=> :order_id, :conditions => {:selected => true}
  many_to_one :client
  one_to_many :catering_extras
  
dataset_module do
    def active
      where(:order_status_id=>[2,4])
    end
  end

  set_dataset(self.active)

  def order_time
    order_for.strftime '%l:%M %p'#'%l:%i %p
  end
  def notes
    last_updates if last_updates.size>1
  end
end