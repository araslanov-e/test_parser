module Providers
  class Sbobet < Base
    module Tennis

      def parse
        @league_events.each do |league_id, raw_league|
          sets_match_pattern = /\s\(Set\sH\w+\)$/
          if (sets_match = raw_league[:name].match(sets_match_pattern)) # leagues like WTA - Bank of the West Classic (Set Handicap)
            raw_league[:name].gsub!(sets_match_pattern, '')
          else
            game_match_pattern = /\s\(Game\sH\w+\)$/
            raw_league[:name].gsub!(game_match_pattern, '')
          end

          @bookmaker_league = create_bookmaker_league(raw_league[:name], league_id)
          @bookmaker_events = bookmaker_events(@bookmaker_league)

          raw_league[:events].each_value do |raw_event|
            # check teams first
            home_team = create_bookmaker_team(raw_event[:home_team].gsub(/\(n\)/, '')) # remove (n)
            away_team = create_bookmaker_team(raw_event[:away_team].gsub(/\(n\)/, '')) # remove (n)

            # creating events
            Time.zone = @time_zone
            event_time = Time.zone.parse(raw_event[:event_date].gsub(/^(\d{2})\/(\d{2})(.+)$/, '\2/\1\3'))
            bookmaker_event = create_bookmaker_event(home_team, away_team, event_time, raw_event[:short_url])



            # bookmaker's bet
            @bets = bookmaker_event.bets
            @bets_to_remove[bookmaker_event.id] = @bets.map(&:id) unless @bets_to_remove[bookmaker_event.id]

            # moneyline
            if raw_event[:moneyline]
              create_or_update_bet(bookmaker_event, -1, 'ML1', nil, raw_event[:moneyline][:ml_1])
              create_or_update_bet(bookmaker_event, -1, 'ML2', nil, raw_event[:moneyline][:ml_2])
            end
            # totals
            if raw_event[:totals]
              raw_event[:totals].each do |t|
                bet_over, bet_under = if sets_match then ['SET_TO', 'SET_TU'] else ['TO', 'TU'] end
                create_or_update_bet(bookmaker_event, -1, bet_over, t[:total], t[:over])
                create_or_update_bet(bookmaker_event, -1, bet_under, t[:total], t[:under])
              end
            end
            # handicaps
            if raw_event[:handicaps]
              raw_event[:handicaps].each do |h|
                bet_f1, bet_f2 = if sets_match then ['SET_F1', 'SET_F2'] else ['F1', 'F2'] end
                create_or_update_bet(bookmaker_event, -1, bet_f1, h[:hand_1], h[:odds_1])
                create_or_update_bet(bookmaker_event, -1, bet_f2, h[:hand_2], h[:odds_2])
              end
            end
            rescan_event(bookmaker_event)
          end
        end
      end

      private

      def parse_money_line(bets_data)
        (moneyline = bets_data.find{ |b| b[1][0] == 11 }) ? { ml_1: moneyline[2][0], ml_2: moneyline[2][1] } : {}
      end
    end
  end
end