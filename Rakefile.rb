require 'googlevoiceapi'
require 'google_drive'
require 'sequel'
require 'yaml'
require 'mail'
require 'gcalapi'


$LOAD_PATH << File.dirname(__FILE__)


task :environment do
  location = ENV['location'] || 'SF'
  @regenerate = ENV['regenerate'] || false
  APP_CONFIG = YAML::load_file("config.yml")[location]
  @google_drive = GoogleDrive.login(APP_CONFIG["google"]["login"], APP_CONFIG["google"]["password"])
  @google_voice = GoogleVoice::Api.new(APP_CONFIG["google"]["login"], APP_CONFIG["google"]["password"])
  @contributors = APP_CONFIG["contributors"]
  @spreadsheet_key = APP_CONFIG["google"]["spreadsheet_key"]
  @worksheet_title = "Daily Order Confirmations #{Date.today.month}/#{Date.today.day}"
  DB = Sequel.connect(
    adapter: 'mysql2', 
    host: APP_CONFIG["db"]["host"],
    database: APP_CONFIG["db"]["database"], 
    user: APP_CONFIG["db"]["username"], 
    password: APP_CONFIG["db"]["password"])
  require 'models/init'
  Mail.defaults do
    delivery_method :smtp, {
      :address              => "smtp.gmail.com",
      :port                 => 587,
      :domain               => "cater2.me",
      :user_name            => APP_CONFIG["google"]["login"],
      :password             => APP_CONFIG["google"]["password"],
      :authentication       =>'plain',
      :enable_starttls_auto => true 
    }
  end
end

task :create_spreadsheet => :environment do
  if @google_drive.file_by_title(@worksheet_title) && @regenerate == false
    puts  "nothing to do"
  else
    worksheet = @google_drive.spreadsheet_by_key(@spreadsheet_key).worksheets[0]
    worksheet.list.each do |row|
      row.clear
    end
    @google_drive.spreadsheet_by_key(@spreadsheet_key).title = @worksheet_title
    worksheet.save
    OrderRequest.for_today.eager_graph([{:order_proposal=>:vendor},{:client=>:company},:client_profile,:catering_extra_labels]).
    order(Sequel.qualify(:vendor,:name), :order_status_id, :order_for,Sequel.qualify(:order_proposal,:id_order_proposal)).all.each do |order|
      if ENV['location'] == 'SF'
        notification = order.order_proposal.vendor.notification_preference
      else
        notification = order.order_proposal.vendor.MorningText != '' ? "To Text" : "To Call"
      end
      worksheet.list.push({
        "Text/Call?" => notification,
        "Primary Number" => order.order_proposal.vendor.MorningText,
        "VendorName" => order.order_proposal.vendor.name,
        "OrderStatus" => order.order_status_id == 2 ? "Canceled" : "Confirmed",
        "OrderForTime" => order.order_time,
        "PhoneNumber" => order.order_proposal.vendor.phone_number2,
        "tbl_Vendor Contact Info.PersonalNumber" => order.order_proposal.vendor.personal_number2,
        "CompanyName" => order.client.name,
        "ProposalNumber" => order.order_proposal.id_order_proposal,
        "UpdateTime" => order.update_time,
        "UpdateNotes" => order.update_notes,
        "ContactFirstName"  => order.order_proposal.vendor.contact_first_name2,
        "SecondaryContacts" => order.order_proposal.vendor.secondary_contacts2,
        "SecondaryNumbers"  => order.order_proposal.vendor.secondary_numbers2,
        "SecondaryNotes"    => order.order_proposal.vendor.secondary_notes2,
        "Food allergies?"   => order.client.client_profile.food_allergies_cl,
        "Notes" => order.notes,
        "Utensils?" => order.catering_extra_labels.collect(&:label).include?("Utensils") ? "TRUE" : "FALSE",
        "Paper Ware?" => order.catering_extra_labels.collect(&:label).include?("Paper Ware") ? "TRUE" : "FALSE",
        "Beverages?" => order.catering_extra_labels.collect(&:label).include?("Beverages") ? "TRUE" : "FALSE",
        "Folding Tables?" => order.catering_extra_labels.collect(&:label).include?("Folding Tables") ? "TRUE" : "FALSE",
        "BuyerAddress" => order.delivery_address,
        "City" => order.delivery_city,
        "tbl_BuyerContactInfo.PersonalNumber" => order.client.contacts_personal_number_cl
      })
    end
    worksheet.save
  end
end

task :message_vendors => :create_spreadsheet do
  worksheet = @google_drive.spreadsheet_by_title(@worksheet_title).worksheets[0]
  row_data, succeeded, failed = [], [], []
  for row in 2..worksheet.num_rows
    if worksheet[row,1].downcase.match(/text/) #TODO: Change to text
      row_data << [Vendor.clean_number(worksheet[row, 2]), worksheet[row, 3]] if worksheet[row, 2] != ""
    end
  end
  row_data = row_data.uniq{ |r| r[0] }
  row_data.each do |r|
    number = r[0]
    vendor_name = r[1]
    message = Vendor.where(name: vendor_name).first.get_message
    status = @google_voice.sms(number, message)
    if status.code.to_i == 200
      succeeded << "#{number} : #{message}"
    else
      failed << "#{number} : #{message}"
    end
    for row in 2..worksheet.num_rows
      worksheet[row, 1] = "Awaiting Response" if Vendor.clean_number(worksheet[row, 2]) == number
      worksheet.save()
    end
  end
  subject = "Text Confirmations Status for #{Date.today} Send #{succeeded.count}; Failed: #{failed.count}"
  content = ["Succeeded:",succeeded.join("\r\n"),"Failed:", failed.join("\r\n")].join("\n")
  send_mail(subject, content)
end

task :message_one_vendor, [:number, :vendor] => :environment do |t, args|
  worksheet = @google_drive.spreadsheet_by_title(@worksheet_title).worksheets[0]
  vendor_name = args[:vendor]
  number = Vendor.clean_number(args[:number])
  message = Vendor.where(name: vendor_name).first.get_message
  status = @google_voice.sms(number, message)
  for row in 2..worksheet.num_rows
    worksheet[row, 1] = "Awaiting Response" if Vendor.clean_number(worksheet[row, 2]) == number
    worksheet.save()
  end
  subject = "Single Text Status #{status.code.to_i} for #{Date.today}"
  content = "#{number} : #{message}"
  send_mail(subject, content)
end

task :test_cron => :environment do 
  File.open('test_file.txt', 'w') { |file| file.write("#{ENV['location']}") }
end

task :wipe_gcal_and_recreate_calendars => :environment do
  last_week = Time.now - (60*60*24*7)
  orders_for_last_week = OrderRequest.orders_for_last_week(last_week, Time.now).all
  if orders_for_last_week == []
    subject = "Database upload failed on #{Date.today}"
    content = "You're going to have to do the calendars at some other point today."
    send_mail(subject, content)
    fail
  else
    Calendar.all.each do |cal|
      sync_calendar(cal)
    end
  end
end

def sync_calendar(cal)
  @srv = GoogleCalendar::Service.new(APP_CONFIG["calendar"]["login"], APP_CONFIG["calendar"]["password"])
  time_min, time_max = Time.now, Time.now + (60*60*24*30)
  formatted_start_min = time_min.strftime("%Y-%m-%dT%H:%M:%S")
  formatted_start_max = time_max.strftime("%Y-%m-%dT%H:%M:%S")
  begin
    cal_id = "cater2.me_" + cal.gcal_id + "@group.calendar.google.com"
    feed = "http://www.google.com/calendar/feeds/"+ cal_id + "/private/full"
    calendar = GoogleCalendar::Calendar.new(@srv, feed)
    events_for_next_month = events(feed, {"start-min" => formatted_start_min, "start-max" => formatted_start_max})
    events_for_next_month.each do |event|
      event.destroy!
      puts "destroyed event for company: #{cal.company.name if cal.company.name}, #{cal.company_id}\n"
    end
    cal.company.clients.each do |client|
      puts "CREATE ORDERS!!"
      puts "#{client.name} #{client.company_id}, client_id: #{client.id_client}\n"
      orders = OrderRequest.orders_for_next_month_for_client(client.id_client, time_min, time_max)
      orders.each do |order|      
        Event.create_events_for_client(calendar, order)
      end
    end
  rescue => e
    error_subject = "GCal Sync Error #{Date.today}"
    error_content = "Error on Company: #{cal.company.name if cal.company.name}, id: #{cal.company_id}\n"
    error_content += e.message
    error_content += "\nretrying for #{cal.company.name if cal.company.name}, id: #{cal.company_id}"
    send_mail(error_subject, error_content)
    puts "retrying for #{cal.company.name if cal.company.name}, id: #{cal.company_id}"
    sync_calendar(cal)
  end
end

def events(feed, conditions = {})
  ret = @srv.query(feed, conditions)
  raise InvalidCalendarURL unless ret.code == "200"
  REXML::Document.new(ret.body).root.elements.each("entry"){}.map do |elem|
    elem.attributes["xmlns:gCal"] = "http://schemas.google.com/gCal/2005"
    elem.attributes["xmlns:gd"] = "http://schemas.google.com/g/2005"
    elem.attributes["xmlns"] = "http://www.w3.org/2005/Atom"
    entry = GoogleCalendar::Event.new
    entry.srv = @srv
    entry.load_xml("<?xml version='1.0' encoding='UTF-8'?>#{elem.to_s}")
  end
end

def send_mail(subject, content)
	Mail.deliver do
	  to APP_CONFIG["status_mail_to"]
	  from APP_CONFIG["status_mail_to"]
	  subject subject
	  body content
	end
end
