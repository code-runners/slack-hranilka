require 'koala'
require 'active_support'
require 'active_support/core_ext'
require 'webrick'

class HranilkaFetcher
  WEEK_DAYS = %w(понеделник вторник сряда четвъртък петък)

  def initialize(access_token) # long lived access token
    @access_token = access_token
  end

  def facebook
    Koala::Facebook::API.new(@access_token)
  end

  def posts
    facebook.get_object('hranilka/feed', fields: ['message,full_picture'])
  end

  def todays_menu
    posts.find { |p| weekday_mentioned?(p['message']) }.try(:fetch, 'full_picture')
  end

  private

  def weekday_mentioned?(message)
    message
      .mb_chars
      .gsub(/[^a-z а-я]/i, ' ')
      .downcase.split(' ')
      .any? { |c| WEEK_DAYS.include?(c.squeeze) }
  end
end

# Server

server = WEBrick::HTTPServer.new Port: 8000

server.mount_proc '/' do |req, res|
  a = HranilkaFetcher.new('***REMOVED***')
  image = a.todays_menu
  if image
    res.body = image
  else
    res.body = "Can'f find the menu for today"
  end
end

Signal.trap('INT') { server.shutdown }

server.start
