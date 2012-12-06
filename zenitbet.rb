module Providers
  class Zenitbet < Base
    URL_ROOT = "http://zenitbet.com/"

    URL_BETLINES = "http://zenitbet.com/line/setdata?onlyview=1&all=1&game=&live=0&timeline=0&ross=1"
    URL_VIEWLINES = "http://zenitbet.com/line/loadline?live="
    URL_BETLINES_LOCAL = Rails.root.join('app', 'modules', 'providers', 'zenitbet', 'data', 'feed.html')

    def initialize(sport = :soccer)
      @time_zone = "Europe/Moscow"
      super(sport)
    end

    def bet_lines(updates_only = false)
      @updates_only = updates_only

      begin
        if @sport == :soccer
          wait_timeout = @bookmaker.settings.find{ |k| k.parameter == 'wait_timeout' }.value.to_i rescue nil
          sleep(wait_timeout) if wait_timeout.present?

          request(URL_BETLINES)
          doc = request(URL_VIEWLINES)
          File.open(URL_BETLINES_LOCAL, 'w'){ |f| f.write(doc) }
        else
          f = File.open(URL_BETLINES_LOCAL, 'r:utf-8')
          cnt = f.read
          time_stamp = f.ctime.to_s
          f.close
          return false if last_modified_time == time_stamp
          doc = Nokogiri::HTML(cnt)
          update_last_modified_time(time_stamp)
        end
      rescue Exception => e
        logger.fatal("Error requesting url: #{e.message}") and return
      end

      before_parse
      # parsing lines
      parse(doc)
      after_parse
    end

    private

    def request(url)
      domain = URL_ROOT
      begin
        @cookie ||= initial_request(domain)
        Nokogiri::HTML(open_uri(url, read_timeout: 30, "Cookie" => @cookie, "Referer" => domain), nil, 'windows-1251')
      rescue Exception => e
        logger.error("Error opening url #{domain}: #{e.message}")
        return false
      end
    end

    def initial_request(url)
      response = open_uri(url, read_timeout: 5)
      response.meta['set-cookie']
    ensure
      response.close if response
    end

    def correct_encoding(name)
      name.force_encoding("windows-1251")
    end
  end

  class ZenitbetError < BaseError; end
end

