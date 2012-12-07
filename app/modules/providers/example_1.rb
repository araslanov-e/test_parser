module Providers
  class Example_1 < Base
    URL_BETLINES = 'http://example.com/sports.html'

    def initialize(sport = :soccer)
      @time_zone = "Europe/Moscow"
      super(sport)
    end

    def bet_lines(updates_only = false)
      @updates_only = updates_only

      begin
        doc = request(URL_BETLINES)
      rescue Exception => e
        logger.fatal("Error requesting #{url}: #{e.message}") and return
      end

      # parsing lines
      parse(doc)
    end

    private

    def request(url)
      doc = Nokogiri::HTML(open(url))
      err = doc.css('error').first # 
      raise ExampleError.new, err.content if err
      doc
    end
  end

  class Example_1Error < BaseError; end
end