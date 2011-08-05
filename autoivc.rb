#! /usr/bin/env ruby
require 'rubygems'
require 'firewatir' # Browser simulator. See watir.com for installation info
require 'pony' # Easy email
# This is confirmed to work with MySite Version 2.0
# You use it to camp ONE class that you're trying to get into. 
# Once a slot in the class opens (Someone drops), an email is sent to notify you.
# You could modify it for multiple classes easily. Or run multiple instances.
# I recommend running it constantly in a virtual machine.

MYSITE_USERNAME = "123456" # MySite username
MYSITE_PASSWORD = "1234" # MySite password

GMAIL_EMAIL = "my@gmail.com" # Your gmail username
GMAIL_PASSWORD = "mygmailpass" # Your gmail password

TICKET_NO = "60735" # Ticket number for the class you're trying to get into.

def mail_me(subject, body)
  Pony.mail(:to => GMAIL_EMAIL, :via => :smtp,
    :body=>body, :subject=>subject, :via_options => {
    :address              => 'smtp.gmail.com',
    :port                 => '587',
    :enable_starttls_auto => true,
    :user_name            => GMAIL_EMAIL,
    :password             => GMAIL_PASSWORD,
    :authentication       => :plain,
    :domain               => "localhost.localdomain"
  })
end
def login
  @browser.text_field(:name=>"UserName").set MYSITE_USERNAME
  @browser.text_field(:name=>"Password").set MYSITE_PASSWORD
  @browser.button(:name=>"LoginUser").click
end
def wait_load
  sleep 1 until @browser.status == "Done"
end
def autoregister(wait=0)
  @browser.close if @browser.html rescue nil
  while !Time.now.hour.between?(6, 23)
    # mysite is only open between 6 am and 11 pm
    puts "Registration is closed. Sleeping"
    sleep 3600 # check the time again in an an hour 
  end
  begin
    @browser = Watir::Browser.new
    sleep wait
    # go to login page
    @browser.goto("https://www1.socccd.cc.ca.us/portal/")
    wait_load
    login
    wait_load
    # go to registration page
    @browser.goto("https://www1.socccd.cc.ca.us/Portal/MySite/Classes/Registration/SelectTerm.aspx")
    wait_load
    @browser.button(:name, "ctl00$BodyContent$Term1_AddDropClasses").click
    wait_load
    @browser.button(:name, "ctl00$BodyContent$btnNextB").click # next button
    wait_load
    if !@browser.text.include? TICKET_NO # error
      p "Some kind of error occurred... rechecking soon" # <-- this never happened in testing
      autoregister 120 # restarts the process after X time
    elsif @browser.text.include? "Class status is full"
      p "Class was full... rechecking in 10 minutes" # <-- this always happened in testing! :P
      autoregister 300 # restarts the process after X time.
    else
      # Class is probably open if the ticket number appears, and "class is full" does not appear
      p "Class was open! Emailing and quitting."    
      begin
        mail_me "Class #{TICKET_NO} appears open!", @browser.div(:class, "imRegular").text # this was sent, confirmed working.
      rescue Exception => mx # this is just in case something failed
        mail_me "Class #{TICKET_NO} appears open!", "Alert! A class you are watching has an open spot! Ticket #: #{TICKET_NO}\nAlso mail error: #{mx.message}"
      end
    end
  rescue Exception => ex
    puts ex.message
    autoregister 120 # restarts the process after X time
  end
end

autoregister # starts the loop

