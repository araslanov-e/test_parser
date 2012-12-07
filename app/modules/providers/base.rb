module Providers
  class Base
    REQUEST_EXCEPTIONS = [ Timeout::Error, Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::ECONNRESET ].freeze # also Errno::ENETUNREACH

    attr_reader :sport # here sport is symbol like :soccer, :baseball

    private

    def initialize(sport)
      @sport = sport

      bookmaker_name = self.class.name.match(/^Providers::(\w+)$/)[1]

      @logger ||= Logger.new("#{Rails.root}/log/#{bookmaker_name.downcase}-#{@sport}.log", 'daily')
      @logger.formatter = Logger::Formatter.new

      # extend Providers::<bookmaker_name>::<sport_name>
      send(:extend, "#{self.class.name}::#{@sport.capitalize}".constantize)
    end
  end

  class BaseError < StandardError; end
end