class OrderRequest < Sequel::Model
  one_to_one :order_proposal, :key=> :order_id, :conditions => {:selected => true}
  one_to_one :client, :primary_key=>:client_id, :key=>:id_client
  one_to_one :client_profile,:primary_key=>:client_profile_id, :key=>:id_profile
  one_to_many :catering_extras
  many_to_many :catering_extra_labels, :join_table=>:catering_extra,:left_key=>:order_request_id,:right_key=>:extra_label_id

  dataset_module do
    def active
      where(:order_status_id=>[2,4])
    end
    def for_today
      where(Sequel.function(:DATE,:order_for)=>(Sequel.function(:DATE,Time.now)))
    end
    def orders_for_next_month_for_client(client, time_min, time_max)
      where("order_for BETWEEN ? and ?", time_min, time_max).where(client_id: client)
    end
    def orders_for_last_week(time_min, time_max)
      where("order_for BETWEEN ? and ?", time_min, time_max)
    end
  end

  set_dataset(self.active)

  def notes
    last_updates if last_updates.size>1
  end


  def order_time
    order_for.strftime '%l:%M %p'#'%l:%i %p
  end
  def update_time
    last_updated.strftime '%l:%M %p' unless last_updated.nil?
  end
  def update_notes
    last_updates if last_updates.size>1
  end

  def delivery_address
    client_profile.delivery_address.length > 1 ? client_profile.delivery_address : client.company.address
  end
  def delivery_city
    client_profile.delivery_city.length > 1 ? client_profile.delivery_city : client.company.city
  end
end