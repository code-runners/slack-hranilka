# encoding: UTF-8

require 'koala'
require 'active_support'
require 'active_support/core_ext'
require 'webrick'

class HranilkaFetcher
  WEEK_DAYS = %w(понеделник вторник сряда четвъртък петък събота неделя)

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
    posts.find_all { |p| p['full_picture'] && p['message'] }
      .find { |p| weekday_mentioned?(p['message']) }
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

class SlackResponder < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    if req.query['token'] != '***REMOVED***'
      res.status = 503
      res.body = 'Forbidden'
    else
      fetcher = HranilkaFetcher.new('***REMOVED***')
      menu = fetcher.todays_menu

      if menu
        payload = slack_payload(menu['message'], image_url: menu['full_picture'], fallback: 'Menu')
      else
        payload = slack_payload('Can\'t find the menu for today')
      end

      res['Content-Type'] = 'application/json'
      res.status = 200
      res.body = JSON.generate(payload)
    end
  end

  def slack_payload(text, attachment)
    payload = {
      response_type: 'in_channel',
      text: text,
      attachments: []
    }
    payload[:attachments] << attachment if attachment
    payload
  end
end

server = WEBrick::HTTPServer.new Port: 8000
server.mount '/', SlackResponder
Signal.trap('INT') { server.shutdown }
server.start
