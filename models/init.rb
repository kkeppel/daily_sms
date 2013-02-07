require 'sequel'
DB = Sequel.connect(ENV['DATABASE_URL'] || 'mysql2://root@localhost/cater2medev')
require_relative "order_request"
require_relative "order_proposal"
require_relative "catering_extra"
require_relative "vendor"
require_relative "company"
require_relative "client"