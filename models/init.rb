require 'sequel'
DB = Sequel.connect(:adapter=>'mysql2', :host=>'cater2.me', :database=>'cater2medev', :user=>'remote_user', :password=>'12@c2me')
require_relative "order_request"
require_relative "order_proposal"
require_relative "catering_extra"
require_relative "vendor"
require_relative "company"
require_relative "client"