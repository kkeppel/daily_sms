class CateringExtra < Sequel::Model
  set_dataset :catering_extra
  many_to_one :order_request
  many_to_one :catering_extra_labels
end