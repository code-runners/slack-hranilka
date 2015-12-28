# encoding: UTF-8

require 'koala'
require 'active_support'
require 'active_support/core_ext'
require 'webrick'

class HranilkaFetcher
  WEEK_DAYS = %w(понеделник вторник сряда четвъртък петък събота неделя)
  FALLBACK_WORDS = %w(меню)

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
    suspected_posts = posts.find_all do |p|
      p['full_picture'] && p['message'] && p['message'].size < 255
    end

    todays_menu =
      suspected_posts.find { |p| weekday_mentioned?(p['message']) }

    if todays_menu.nil?
      todays_menu =
        suspected_posts.find { |p| fallback_word_mentioned?(p['message']) }
    end
  end

  private

  def weekday_mentioned?(message)
    word_mentioned?(message, WEEK_DAYS)
  end

  def fallback_word_mentioned?(message)
    word_mentioned?(message, FALLBACK_WORDS)
  end

  def word_mentioned?(message, words)
    message
      .mb_chars
      .gsub(/[^a-z а-я]/i, ' ')
      .downcase.split(' ')
      .any? { |c| words.include?(c.squeeze) }
  end
end

# Server

class SlackResponder < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    if req.query['token'] != ENV['SLACK_TOKEN']
      res.status = 503
      res.body = 'Forbidden'
    else
      fetcher = HranilkaFetcher.new(ENV['FACEBOOK_TOKEN'])
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

  def slack_payload(text, attachment = nil)
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
