class CateringExtra < Sequel::Model
	set_dataset :catering_extra
	many_to_one :order_request

	def self.get_extras(order_id)
		find_by_sql(
			"SELECT *
			FROM catering_extra
			WHERE order_request_id = '#{order_id}'
				AND (extra_label_id = 3 OR extra_label_id = 2)")
	end
  dataset_module do
    def with_labels
      where(:extra_label_id=>[2,3])
    end
  end
  set_dataset(self.with_labels)

end