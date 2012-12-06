module Providers
  class Sbobet < Base
    URL_ROOT = "http://www.sbobet.com"
    URL_LEAGUES_JS = '/en/resource/e/euro-dynamic.js?%s'
  	URL_BETLINES = '/euro/%s'

    MAX_DOMAIN_FAILURES = 50

  	def initialize(sport = :soccer)
      @time_zone = "Asia/Hong_Kong"
      super(sport)

      @domains = [
        #{ url: 'http://www.sbobet.com', failures: 0, cookie: nil },
        { url: 'http://www.sbobet2.com', failures: 0, cookie: nil }
        #{ url: 'http://www.sbo666.com', failures: 0, cookie: nil },
        #{ url: 'http://www.sbo2.com', failures: 0, cookie: nil },
        #{ url: 'http://www.sbo128.com', failures: 0, cookie: nil }
      ]
  	end

  	def bet_lines(updates_only = false)
      @updates_only = updates_only

      # requesting leagues
      begin
        leagues = parse_leagues
      rescue Exception => e
        logger.fatal("Error parsing leagues: #{e.message}") and return
      end

      threads = []
      mutex = Mutex.new
      # gathering leagues and events for nearest 8 days, each event has each own page with bet lines
      @league_events = {}
      (0).upto(7) do |i|
        page_url = URL_BETLINES % @bookmaker_sport.identifier # today
        page_url << '/' << (Date.today + i).to_s if i.between?(1, 6) # six days in advance
        page_url << '/more' if i == 7 # more

        threads << Thread.new(page_url) do |url|
          sleep(rand(3))

          begin
            page = request(url)
          rescue Exception => e
            logger.error("Error requesting #{url}: #{e.message}")
            Thread.current.kill
          end

          unless (script = page.at("//script[contains(.,'function initiateOddsDisplay()')]").content)
            logger.error("Unable to find 'function initiateOddsDisplay()' on #{url}")
            Thread.current.kill
          end

          data = parse_events(script)
          if not data or data[0] != 2 # no non-live events
            logger.error("Failed to find non-live events on #{url}")
            Thread.current.kill
          end

          data[1].each do |data_item|
            league_id = data_item[1]
            league_name = leagues[league_id]

            unless league_name =~ /winner|first basket|last basket|\(major league baseball\)$/i # skip some unnecessary leagues
              event_id, home_team, away_team, _, _, event_date = data_item[2]
              url_params = [@bookmaker_sport.identifier, league_name, event_id, home_team, away_team].map{ |i| adjust_item(i) }

              mutex.synchronize do
                @league_events[league_id] ||= { name: league_name,  events: {} }
                @league_events[league_id][:events][event_id] = {
                    home_team: home_team,
                    away_team: away_team,
                    event_date: event_date,
                    url: "#{URL_BETLINES}/%s/%s/%s-vs-%s" % url_params,
                    short_url: "#{URL_BETLINES}/%s/%s" % url_params
                }
              end
            end
          end
        end
      end
      threads.map(&:join)

      threads = []
      # gathering events bet lines
      @league_events.each_value do |league|
        league[:events].each_value do |event|
          next unless event[:url]

          threads << Thread.new(event) do |evt|
            sleep(rand(3)) # timeout

            begin
              event_page = request(evt[:url])
            rescue Exception => e
              logger.error("Error requesting #{evt[:url]}: #{e.message}")
              Thread.current.kill
            end

            # check if we're on a correct page
            unless event_page.at("title[contains('#{evt[:home_team]} -vs- #{evt[:away_team]}')]")
              logger.error("Incorrect page: '#{event_page.at("title").content}' instead of '#{evt[:home_team]} -vs- #{evt[:away_team]} ...'")
              Thread.current.kill
            end

            unless (script = event_page.at("//script[contains(.,'function initiateOddsDisplay()')]").content)
              logger.error("Unable to find 'function initiateOddsDisplay()' on #{evt[:url]}")
              Thread.current.kill
            end

            unless (data = parse_events(script))
              logger.error("Unable to parse 'function initiateOddsDisplay()' data on #{evt[:url]}")
              Thread.current.kill
            end

            bets_data = data[1][0][3]
            # asian handicap
            if (handicaps = bets_data.select{ |b| b[1].is_a?(Array) && b[1][0] == 1 })
              # the sign of handicap belongs to the second team
              evt[:handicaps] = handicaps.collect{ |t| { hand_1: -1 * t[1][5], odds_1: t[2][0], hand_2: t[1][5], odds_2: t[2][1] } }
            end
            # totals
            if (totals = bets_data.select{ |b| b[1][0] == 3 })
              evt[:totals] = totals.collect{ |t| { total: t[1][5], over: t[2][0], under: t[2][1] } }
            end
            # moneyline
            evt[:moneyline] = parse_money_line(bets_data)
            # 1st half asian handicap
            if (_1st_handicaps = bets_data.select{ |b| b[1][0] == 7 })
              # the sign of handicap belongs to the second team
              evt[:_1st_handicaps] = _1st_handicaps.collect{ |t| { hand_1: -1 * t[1][5], odds_1: t[2][0], hand_2: t[1][5], odds_2: t[2][1] } }
            end
            # 1st half moneyline
            if (_1st_moneyline = bets_data.find{ |b| b[1][0] == 8 })
              evt[:_1st_moneyline] = { _1: _1st_moneyline[2][0], _x: _1st_moneyline[2][1], _2: _1st_moneyline[2][2] }
            end
            # 1st half totals
            if (_1st_totals = bets_data.select{ |b| b[1][0] == 9 })
              evt[:_1st_totals] = _1st_totals.collect{ |t| { total: t[1][5], over: t[2][0], under: t[2][1] } }
            end
            # double chance
            if (doublechance = bets_data.find{ |b| b[1][0] == 15 })
              # 1X and X2 are interchanged
              evt[:doublechance] = { _1x: doublechance[2][2], _12: doublechance[2][1], _x2: doublechance[2][0] }
            end
            # odd/even
            if (odd_even = bets_data.find{ |b| b[1][0] == 2 })
              evt[:odd_even] = { odd: odd_even[2][0], even: odd_even[2][1] }
            end
          end
          # process 50 tasks in a row
          if threads.length >= 50
            threads.map(&:join)
            threads.clear
          end
        end
      end
      threads.map(&:join)

      before_parse
      # parsing lines
      parse
      after_parse
  	end

  	private

    def adjust_item(item)
      item.to_s.downcase.gsub(/[\s&]/, '-')
    end

    def request_domain(index = nil)
      return @domains[index.to_i][:url] if index
      # always try firstly get http://sbobet.com
      return @domains[0] if @domains[0][:failures] <= MAX_DOMAIN_FAILURES
      # and random from other else
      result = @domains.select{ |d| d[:failures] <= MAX_DOMAIN_FAILURES }
      result[rand(result.length - 1)]
    end

    def request(query_string)
      domain = request_domain
      raise SbobetError.new, "Unable to find appropriate domain" unless domain

      begin
        domain[:cookie] ||= initial_request(domain[:url])
        Nokogiri::HTML(open_uri(domain[:url] + query_string, read_timeout: 5, "Cookie" => domain[:cookie], "Referer" => domain[:url]))
      rescue Exception => e
        #domain[:failures] += 1
        logger.error("Error opening url #{domain[:url]} (#{domain[:failures]}): #{e.message}")
        request(query_string) # initiate new request, this will continue until all domain become failed
      end
    end

    def initial_request(url)
      response = open_uri(url, read_timeout: 5)
      response.meta['set-cookie']
    ensure
      response.close if response
    end

    def parse_leagues
      script = request(URL_LEAGUES_JS % Digest::MD5.hexdigest(Time.now.to_i.to_s)[0...8]).content

      start_pos = script.index(/\.setElement\('tournaments',\s?\[/)
      end_pos = script.index(/\]\);/, start_pos)
      JSON.parse(script[(start_pos + 26)..end_pos].gsub(/'/, '"').gsub(/\\"/, '\'')).inject({}) do |res, league|
        res[league[0]] = league[1]; res
      end
    end

    def parse_events(str)
      # remove all before except $P.onUpdate(...);
      str.gsub!(/.*(\$P\.onUpdate\(.*\);).*/, '\1')

      2.times do |i|
        str = str[str.index(/\[/, i)..str.rindex(/\]/, -(i + 1))]
      end

      # remove such garbage {...}, e.g. {126:[1,5,10,15,0,0,null,"HT"]}
      str.gsub!(/\,\{([\w\:\[\]\,\"\']*)?\}/, '')
      2.times{ str.gsub!(/\,\,/, ',') }
      str.gsub!(/\,(\])/, '\1')

      # replace ' with " to support json format
      str.gsub!(/'/, '"')
      str.gsub!(/\\"/, '\'')

      JSON.parse(str).last
    end
  end

  class SbobetError < BaseError; end
end