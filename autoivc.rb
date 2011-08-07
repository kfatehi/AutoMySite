#! /usr/bin/env ruby
require 'rubygems'
if File.exists? "config.rb"
  load "config.rb"
else
  puts %{\nPlease add the following to config.rb before proceeding:\n
  MYSITE_USERNAME = "000000" # Your MySite username
  MYSITE_PASSWORD = "0000" # Your MySite password
  GMAIL_EMAIL = "you@gmail.com" # Your gmail username
  GMAIL_PASSWORD = "your_gmail_pass" # Your gmail password
  TICKETS = [00000, 11111, 22222] # Classes you're trying to add\n\n}
  exit
end

class Logger
  def initialize(filepath)
    @logfile = filepath
    File.open(@logfile, 'w') do |f|
      f.puts "<pre>New session started @ #{Time.now}"
      f.puts "Setting up to watch tickets: #{TICKETS.join(' ')}"
    end
  end
  def print(msg)
    File.open(@logfile, 'a') do |f|
      f.print msg
    end
  end
  def puts(msg)
    File.open(@logfile, 'a') do |f|
      f.puts msg
    end
  end
end

class Mailer
  require 'pony' # Easy email
  def initialize(gmail_email, gmail_password, to=nil)
    @opts = {
      :to => to||=gmail_email, :via => :smtp,
      :body=>"", :subject=>"", :via_options => {
        :address              => 'smtp.gmail.com',
        :port                 => '587',
        :enable_starttls_auto => true,
        :user_name            => GMAIL_EMAIL,
        :password             => GMAIL_PASSWORD,
        :authentication       => :plain,
        :domain               => "localhost.localdomain"
      }
    }
  end
  
  def deliver(subject, body)
    $log.puts "Attempting to send email:\nSubject:#{}"
    @opts[:subject] = subject
    @opts[:body] = body
    Pony.mail(@opts)
  end
  
  def deliver_alert_class_open(ticket_no)
    deliver "ALERT Class Open: #{ticket_no}",
      "Notification that class with ticket # #{ticket_no} is currently OPEN!"
  end
  
  def deliver_registration_success(ticket_no)
    deliver "SUCCESS Class Registered: #{ticket_no}",
      "Notification that class with ticket # #{ticket_no} has been REGISTERED!"
  end
  
end

module Constants
  MAIN_URL = "https://www1.socccd.cc.ca.us/portal/"
  SCHEDULE_BUILDER_URL = "https://www1.socccd.cc.ca.us/Portal/MySite/Classes/Registration/SelectTerm.aspx"
  SCHEDULE_BUILDER_BUTTON_NAME = "ctl00$BodyContent$Term1_AddDropClasses"
  TICKET_TEXTFIELD_NAME = "ctl00$BodyContent$ucScheduleBuilder$txtTicketNumber"
  TICKET_SUBMIT_NAME = "ctl00$BodyContent$ucScheduleBuilder$btnAddClass"
  AJAX_RESPONSE_DIV_ID = "ctl00_BodyContent_ucScheduleBuilder_updImportantMessages"
  SUCCESS_MSG = "successfully added"
  PENDING_TABLE_ID = "ctl00_BodyContent_ucScheduleBuilder_PendingClassesUpdatePanel"
  REGISTER_NEXT_BUTTON_NAME = "ctl00$BodyContent$ucScheduleBuilder$btnNextB"
  REGISTER_NEXT_NEXT_BUTTON_NAME = "ctl00$BodyContent$btnNextB"
  MONEY_ORDER_RADIO_NAME = "ctl00$BodyContent$PaymentGroup"
  CHECKOUT_TABLE_ID = "ctl00_BodyContent_CheckoutSummaryStep_grdEnrolledClasses"
  CHECK_OR_MONEY_ORDER_RADIO_VALUE = "rdbCheckMoney"
end

class Agent
  require 'firewatir' # Browser simulator. See watir.com for installation info
  include Constants
  attr_accessor :ff
  
  def initialize(username, password)
    @ff = Watir::Browser.new
    @ff.goto(MAIN_URL)
    self.login(username, password)
  end
  
  def login(username, password)
    @ff.text_field(:name=>"UserName").set username
    @ff.text_field(:name=>"Password").set password
    @ff.button(:name=>"LoginUser").click
  end
  
  def load_schedule_builder
    @ff.goto(SCHEDULE_BUILDER_URL)
    @ff.button(:name, SCHEDULE_BUILDER_BUTTON_NAME).click
  end
  
  def try_adding_class(ticket_no)
    # Returns either the response text, or false for timeout
    $log.print "."
    self.load_schedule_builder
    temp = @ff.div(:id=>AJAX_RESPONSE_DIV_ID).text
    @ff.text_field(:name=>TICKET_TEXTFIELD_NAME).set ticket_no
    @ff.button(:name=>TICKET_SUBMIT_NAME).click
    wait_count = 0
    while @ff.div(:id=>AJAX_RESPONSE_DIV_ID).text == temp
      wait_count > 5 ? (return false) : wait_count+=1
      sleep 1 # Wait a few seconds for ajax, if nothing, return false
    end
    return @ff.div(:id=>AJAX_RESPONSE_DIV_ID).text
  end
  
  def try_registering_class(ticket_no)
    # FIXME bail if ticket_no is already in the registered classes table
    unless @ff.button(:name=>REGISTER_NEXT_BUTTON_NAME).exist?
      self.load_schedule_builder
    end
    $log.print "R"
    @ff.button(:name=>REGISTER_NEXT_BUTTON_NAME).click
    @ff.button(:name=>REGISTER_NEXT_NEXT_BUTTON_NAME).click
    @ff.radio(:value=>CHECK_OR_MONEY_ORDER_RADIO_VALUE).set 
    @ff.button(:name=>REGISTER_NEXT_NEXT_BUTTON_NAME).click
    sleep 10 # Give the ajaxy checkout process plenty of time...
    if @ff.table(:id=>CHECKOUT_TABLE_ID).text.include?("Enrolled #{ticket_no}")
      $log.print "S"
      return true
    else
      $log.print "F"
      return false
    end
  end
  
  def is_class_open?(ticket_no)
    $log.print "?"
    if response = self.try_adding_class(ticket_no)
      if response.include?(SUCCESS_MSG)
        $log.print "O" # Open
        return true # Class appears to be open.
      else
        $log.print "C" # Closed
        return false
      end
    else # Adding class timed out... Maybe we actually added the class.
      self.load_schedule_builder # Reload the schedule builder and check.
      if @ff.table(:id=>PENDING_TABLE_ID).text.include?(ticket_no)
        $log.print "P" # Pending Registration
        return true # Class appears to be open, we're pending registration
      else
        $log.print "T" # Request Timeout
        return false
      end
    end
  end
  
end

class CourseDelegate
  # Wrapper class for the course, binding together its ticket number,
  # a browser simulation Agent loaded with MySite credentials,
  # and finally a Mailer object loaded with GMail credentials.
  attr_accessor :id
  def self.wrap(options)
    o[:tickets].map do |id|
      self.new(id, o[:agent], o[:mailer])
    end
  end
  
  def initialize(ticket_no, agent, mailer)
    @id = ticket_no.to_s
    @agent = agent
    @mailer = mailer
    @registered = false
  end
  
  def open?
    unless @registered
      if res = @agent.is_class_open?(@ticket_no)
        @mailer.deliver_alert_class_open @id
      end
      return res
    end
  end
  
  def register!
    if self.open?
      if @agent.try_registering_class @ticket_no
        @mailer.deliver_registration_success @id
        @registered == true
      else
        @registered == false
      end
    end
  end
  
end

$log = Logger.new(LOGFILE)

while true
  until Time.now.hour.between?(6, 23)
    $log.print "S" # Registration is closed from 11PM to 6AM
    sleep 900 # Check the time every 15 minutes.
  end
  CourseDelegate.wrap({
    :tickets => TICKETS,
    :agent => Agent.new(MYSITE_USERNAME, MYSITE_PASSWORD),
    :mailer => Mailer.new(GMAIL_EMAIL, GMAIL_PASSWORD),
  }).each do |course|
    begin
      $log.puts "Current course: #{course.id}"
      course.register!
    rescue Exception => ex
      $log.puts ex.message
      $log.puts ex.backtrace
    end
  end
end
