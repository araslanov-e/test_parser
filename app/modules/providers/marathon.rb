require 'nokogiri'

module Providers
  class Marathon < Base
    URL_ROOT = 'http://www.marathonbet.com/en/'
    URL_BETLINES = 'http://www.marathonbet.com/en/betting/%s'
    URL_ADDITIONAL_LINES = 'http://www.marathonbet.com/en/markets.htm?isHotPrice=false&treeId=%s'

    def initialize(sport = :soccer)
      @time_zone = "Europe/London"
      super(sport)
    end

    def bet_lines(updates_only = false)
      @updates_only = updates_only

      begin
        doc = request(URL_BETLINES % @bookmaker_sport.identifier)
      rescue Exception => e
        logger.fatal("Error requesting #{URL_BETLINES % bookmaker_sport.identifier}: #{e.message}") and return
      end

      before_parse
      # parsing lines
      parse(doc)
      after_parse
    end

    private

    def request(url)
      Nokogiri::HTML(open_uri(url))
    end

    def parse_node(node, in_brackets = false)
      if in_brackets
        node.try{ |n| n.content.scan(/\((.+)\)/).flatten.first }.try(:strip)
      else
        node.at("span:not(.igrey)").try{ |n| n.content.strip }
      end
    end
  end

  class MarathonError < BaseError; end
end