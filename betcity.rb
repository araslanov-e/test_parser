module Providers
  class Betcity < Base
    URL_ROOT = "http://betcity.ru"
    URL_LANGUAGE = "http://betcityru.com/lngswitch.php?lang=%s"
    URL_LEAGUES = "http://betcityru.com/bets/bets.php"
    URL_BETLINES = "http://betcityru.com/bets/bets2.php?rnd=%d"
    URL_STAKE = "http://betcityru.com/bt/?bb=%s"
    URL_LOGIN = "http://betcityru.com/top.php"
    URL_BETLINES_LOCAL = Rails.root.join('app', 'modules', 'providers', 'betcity', 'data', 'feed.html')

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

          begin
            initial_request
          rescue Exception => e
            logger.fatal("Error making initial request: #{e.message}") and return
          end

          # leagues
          #post_params = [['line_id[]', @bookmaker_sport.identifier]]
          begin
            page = @agent.get(URL_LEAGUES)
          rescue Exception => e
            logger.fatal("Error requesting #{URL_LEAGUES}: #{e.message}") and return
          end

          raw_leagues = page.search("//table/tr/td[@class='bt']/input[@name='line_id[]']")

          # leagues + events
          post_params = raw_leagues.inject([]){ |res, l| res << ['line_id[]', l[:value]]; res }
          post_params += [['simple', 'on'], ['dop', 1], ['time', 1], ['gcheck', 9]]

          doc = @agent.post(URL_BETLINES % Time.now.utc.to_i, post_params)
          File.delete URL_BETLINES_LOCAL rescue nil
          doc.save URL_BETLINES_LOCAL
        else
          f = File.open(URL_BETLINES_LOCAL, 'r:windows-1251:utf-8')
          cnt = f.read
          time_stamp = f.ctime.to_s
          f.close
          return false if last_modified_time == time_stamp
          doc = Nokogiri::HTML(cnt)
          update_last_modified_time(time_stamp)
        end
      rescue Exception => e
        #logger.fatal("Error making post request #{page.uri.to_s}: #{e.message}") and return
        logger.fatal("Error making post request: #{e.message}") and return
      end

      before_parse
      # parsing lines
      parse(doc)
      after_parse
    end

    private

    def initial_request
      parse_username = @bookmaker.settings.find{ |k| k.parameter == 'parse_username' }.value rescue nil
      parse_password = @bookmaker.settings.find{ |k| k.parameter == 'parse_password' }.value rescue nil

      @agent = mechanize_agent

      # make some initial requests
      @agent.post(URL_LOGIN, [["login", parse_username], ["pwd", parse_password], ["x", "10"], ["y", "9"]])
      @agent.get(URL_LANGUAGE % 'en')
    end

    def parse_totals(line)
      # Total: (0.5) Under 7.5; Over 1.06;
      total_matches = line.match(/Total:\s\(([\d\.]+)\)\s?(Under\s([\d\.]+);)?\s?(Over\s([\d\.]+);)?/)
      total_matches ? [total_matches[1], total_matches[3], total_matches[5]] : [nil] * 3
    end

    def parse_baseline(bookmaker_event, period, _moneyline, _1x2, _doublechance, _homespread, _awayspread, _totals, _hometotals, _awaytotals)

      if _moneyline
        ml_1, ml_2 = _moneyline
        create_or_update_bet(bookmaker_event, period, 'ML1', nil, ml_1[:content], ml_1[:link]) if ml_1
        create_or_update_bet(bookmaker_event, period, 'ML2', nil, ml_2[:content], ml_2[:link]) if ml_2
      end

      if _homespread # handicap 1
        hand_1, odds_1 = _homespread
        create_or_update_bet(bookmaker_event, period, 'F1', hand_1[:content], odds_1[:content], odds_1[:link]) if hand_1
      end

      if _awayspread # handicap 2
        hand_2, odds_2 = _awayspread
        create_or_update_bet(bookmaker_event, period, 'F2', hand_2[:content], odds_2[:content], odds_2[:link]) if hand_2
      end

      if _1x2
        _1, _x, _2 = _1x2
        create_or_update_bet(bookmaker_event, period, '1', nil, _1[:content], _1[:link]) if _1
        create_or_update_bet(bookmaker_event, period, 'X', nil, _x[:content], _x[:link]) if _x
        create_or_update_bet(bookmaker_event, period, '2', nil, _2[:content], _2[:link]) if _2
      end

      if _doublechance
        _1x, _12, _x2 = _doublechance
        create_or_update_bet(bookmaker_event, period, '1X', nil, _1x[:content], _1x[:link]) if _1x
        create_or_update_bet(bookmaker_event, period, '12', nil, _12[:content], _12[:link]) if _12
        create_or_update_bet(bookmaker_event, period, 'X2', nil, _x2[:content], _x2[:link]) if _x2
      end

      if _totals
        _totals.each do |t|
          total_1, under_1, over_1 = t
          if total_1
            create_or_update_bet(bookmaker_event, period, 'TO', total_1[:content], over_1[:content], over_1[:link])
            create_or_update_bet(bookmaker_event, period, 'TU', total_1[:content], under_1[:content], under_1[:link])
          end
        end
      end

      if _hometotals # home ind. totals
        ind_total_1, ind_under_1, ind_over_1 = _hometotals
        if ind_total_1
          create_or_update_bet(bookmaker_event, period, 'I1TO', ind_total_1[:content], ind_over_1[:content], ind_over_1[:link])
          create_or_update_bet(bookmaker_event, period, 'I1TU', ind_total_1[:content], ind_under_1[:content], ind_under_1[:link])
        end
      end

      if _awaytotals # away ind. totals
        ind_total_2, ind_under_2, ind_over_2 = _awaytotals
        if ind_total_2
          create_or_update_bet(bookmaker_event, period, 'I2TO', ind_total_2[:content], ind_over_2[:content], ind_over_2[:link])
          create_or_update_bet(bookmaker_event, period, 'I2TU', ind_total_2[:content], ind_under_2[:content], ind_under_2[:link])
        end
      end
    end

    def parse_handicaps(line, team_1, team_2)
      team_1_matches = line.match(/Handicap:\s?#{Regexp.escape(team_1)}:\s\(([\+\-\d\.]+)\)\s([\d\.]+)/)
      hand_1, value_1 = team_1_matches ? [team_1_matches[1], team_1_matches[2]] : [nil] * 2

      team_2_matches = line.match(/[:;]\s?#{Regexp.escape(team_2)}:\s\(([\+\-\d\.]+)\)\s([\d\.]+)/)
      hand_2, value_2 = team_2_matches ? [team_2_matches[1], team_2_matches[2]] : [nil] * 2

      [team_1, hand_1, value_1, team_2, hand_2, value_2]
    end

    def parse_ind_totals(line, team_1, team_2)
      # Ind. Total: FC Brest: (1) Under 2.1; Over 1.65; Belshina: (1) Under 1.72; Over 2;
      team_1_matches = line.match(/Ind\.\sTotal:\s?#{Regexp.escape(team_1)}:\s\(([\d\.]+)\)\s?(Under\s([\d\.]+);)?\s?(Over\s([\d\.]+);)?/)
      total_1, under_1, over_1 = team_1_matches ? [team_1_matches[1], team_1_matches[3], team_1_matches[5]] : [nil] * 3

      team_2_matches = line.match(/[:;]\s+#{Regexp.escape(team_2)}:\s\(([\d\.]+)\)\s?(Under\s([\d\.]+);)?\s?(Over\s([\d\.]+);)?/)
      total_2, under_2, over_2 = team_2_matches ? [team_2_matches[1], team_2_matches[3], team_2_matches[5]] : [nil] * 3

      [team_1, total_1, under_1, over_1, team_2, total_2, under_2, over_2]
    end
  end

  class BetcityError < BaseError; end
end

