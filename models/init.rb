require 'sequel'
if ENV['DATABASE']
  DB = Sequel.connect(:adapter=>'mysql2', :host=>ENV['DATABASE']['host'], :database=>ENV['DATABASE']['database'], :user=>ENV['DATABASE']['user'], :password=>ENV['DATABASE']['password'])
else
  DB = Sequel.connect('mysql2://root@localhost/cater2medev')
end
require_relative "order_request"
require_relative "order_proposal"
require_relative "catering_extra"
require_relative "vendor"
require_relative "company"
require_relative "client"