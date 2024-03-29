#! /usr/bin/env ruby
=begin ========== LICENSE & DISCLAIMER
Copyright 2011 Keyvan Fatehi. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of
      conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice, this list
      of conditions and the following disclaimer in the documentation and/or other materials
      provided with the distribution.

THIS SOFTWARE IS PROVIDED BY KEYVAN ''AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL KEYVAN OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those of the
authors and should not be interpreted as representing official policies, either expressed
or implied, of Keyvan Fatehi.

THIS IS FOR EDUCATIONAL PURPOSES ONLY. I AM NOT RESPONSIBLE OR LIABLE FOR YOUR USE HEREIN
=end

MYSITE_USERNAME = "123456"
MYSITE_PASSWORD = "1234"
GMAIL_EMAIL = "you@gmail.com"
GMAIL_PASSWORD = "your_gmail_password"
TICKETS = %w(63040 63315 63090) # the class or classes you want to register
LOGFILE = "/path/to/my_log.html" # if you want to use the log feature

=begin ========== ABOUT, INSTRUCTIONS, REQUIREMENTS
This script will help you get into a class at any MySite-driven college such as
IVC or Saddleback. In order to use this script, you will need to have a system
with the following setup, recommended on Ubuntu (maybe a headless VirtaulBox VM):
* Ruby 1.8.7 or newer
* Firefox 3.6 + JSSH http://wiki.openqa.org/display/WTR/FireWatir+Installation
* The following gems: pony, firewatir
In order to receive email, make sure your ruby is linked with openssl, otherwise
you will not receive alert emails. The script will email you when a class is open
or when it has been successfully registered. It will also put you on priority add list.
To begin, make sure you fill out the options above, such as username, and class IDs.
Once you've done all that, you can run the script like any other ruby script.

If you want to make improvements, here are some things that would be cool:
Detect when in Credit Card only mode (after semester begins they disable money order)
Accept insertion of credit card info automatically.
=end

require 'rubygems'

class Logger
  def initialize(filepath)
    @logfile = filepath
    title = "<title>AutoMySite</title>"
    js = %{<script>
      window.onload = function () {
        window.scrollTo(0, document.body.scrollHeight);
        setTimeout('window.location.reload()', 5000);
      }</script>
    }
    File.open(@logfile, 'w') do |f|
      f.puts "<html><head>#{title}#{js}</head><body>"
      f.puts "<pre>New session started @ #{Time.now}"
      f.puts "Watching tickets: #{TICKETS.join(' ')}"
      f.puts "<p><b>LOG LEGEND</b><ul><li>'+' Attempted to add class</li>"
      f.puts "<li>'O' Class detected as OPEN.</li>"
      f.puts "<li>'C' Class detected as CLOSED.</li>"
      f.puts "<li>'P' Class pending registration.</li>"
      f.puts "<li>'R' Will try to register class now.</li>"
      f.puts "<li>'S' Registration was a success.</li>"
      f.puts "<li>'F' Failed to register for the class.</li>"
      f.puts "<li>'T' Request timed out.</li></ul></p>"
      
    end
  end
  def print(msg)
    File.open(@logfile, 'a') do |f|
      f.print msg
    end
  end
  def puts(msg)
    File.open(@logfile, 'a') do |f|
      f.puts "\n#{msg}"
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

module MySite
  def self.closed?
    !Time.now.hour.between?(6, 22)
  end
  # These may change / break / etc, so they are conveniently constantized below:
  MAIN_URL = "https://www1.socccd.cc.ca.us/portal/"
  SCHEDULE_BUILDER_URL = "https://www1.socccd.cc.ca.us/Portal/MySite/Classes/Registration/SelectTerm.aspx"
  SCHEDULE_BUILDER_BUTTON_NAME_0 = "ctl00$BodyContent$Term0_AddDropClasses"
  SCHEDULE_BUILDER_BUTTON_NAME_1 = "ctl00$BodyContent$Term1_AddDropClasses"
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
  PRIORITY_ADD_LIST_SUBMIT_BUTTON_NAME = "ctl00$BodyContent$ucScheduleBuilder$btnPalDialogYes"
end

class Agent
  require 'firewatir' # Browser simulator. See watir.com for installation info
  include MySite
  attr_accessor :ff
  
  def initialize(username, password)
    @ff = Watir::Browser.new
    @ff.goto(MAIN_URL)
    @username = username
    @password = password
    self.login(username, password)
  end
  
  def login(username, password)
    @ff.text_field(:name=>"UserName").set username
    @ff.text_field(:name=>"Password").set password
    @ff.button(:name=>"LoginUser").click
  end
  
  def load_schedule_builder
    @ff.goto(SCHEDULE_BUILDER_URL)
    if @ff.text_field(:name=>"UserName").exists?
      self.login(@username, @password)
      @ff.goto(SCHEDULE_BUILDER_URL)
    end
    if @ff.button(:name, SCHEDULE_BUILDER_BUTTON_NAME_1).exists?
      @ff.button(:name, SCHEDULE_BUILDER_BUTTON_NAME_1).click
    elsif @ff.button(:name, SCHEDULE_BUILDER_BUTTON_NAME_0).exists?
      @ff.button(:name, SCHEDULE_BUILDER_BUTTON_NAME_0).click
    end
  end
  
  def try_adding_class(ticket_no)
    # Returns either the response text, or false for timeout
    $log.print "+"
    self.load_schedule_builder
    temp = @ff.div(:id=>AJAX_RESPONSE_DIV_ID).text
    @ff.text_field(:name=>TICKET_TEXTFIELD_NAME).set ticket_no
    @ff.button(:name=>TICKET_SUBMIT_NAME).click
    wait_count = 0
    while @ff.div(:id=>AJAX_RESPONSE_DIV_ID).text == temp
      wait_count > 10 ? (return false) : wait_count+=1
      sleep 1 # Wait a few seconds for ajax, if nothing, return false
    end
    if @ff.button(:name=>PRIORITY_ADD_LIST_SUBMIT_BUTTON_NAME).exists?
      @ff.button(:name=>PRIORITY_ADD_LIST_SUBMIT_BUTTON_NAME).click
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
  def self.wrap(o)
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
      if res = @agent.is_class_open?(@id)
        @mailer.deliver_alert_class_open @id
      end
      return res
    end
  end
  
  def register!
    if self.open?
      if @agent.try_registering_class @id
        @mailer.deliver_registration_success @id
        @registered == true
      else
        @registered == false
      end
    end
  end
  
end

$log = Logger.new(LOGFILE.blank? ? "log.html" : LOGFILE)
courses = CourseDelegate.wrap({
  :tickets => TICKETS,
  :agent => Agent.new(MYSITE_USERNAME, MYSITE_PASSWORD),
  :mailer => Mailer.new(GMAIL_EMAIL, GMAIL_PASSWORD),
})
while true
  if MySite.closed?
    $log.puts "MySite is closed, sleeping..."
    while MySite.closed?
      $log.print "z"
      sleep 900 # Check the time every 15 minutes.
    end
    $log.puts "MySite has reopened. Waking up."
  end
  courses.each do |course|
    begin
      $log.puts "Current course: #{course.id}"
      course.register!
    rescue Exception => ex
      $log.puts ex.message
      $log.puts ex.backtrace
    end
  end
end
