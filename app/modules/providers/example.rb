module Providers
  class Example < Base
    URL_BETLINES = 'http://example.com/feed.xml'

    def initialize(sport = :soccer)
      super(sport)
    end

    def bet_lines(updates_only = false)
      @updates_only = updates_only

      begin
        #doc = request(URL_BETLINES)
        doc = Nokogiri::XML(open(Rails.root.join('app', 'modules', 'providers', 'example', 'data', 'feed.xml')))
      rescue Exception => e
        logger.fatal("Error requesting #{url}: #{e.message}") and return
      end
      # parsing lines
      parse(doc)
    end

    private

    def request(url)
      doc = Nokogiri::XML(open(url))
      err = doc.css('error').first
      raise ExampleError.new, err.content if err
      doc
    end
  end

  class ExampleError < BaseError; end
end