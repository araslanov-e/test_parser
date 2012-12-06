module Providers
  class Sbobet < Base
    module Snooker

      def parse
        @league_events.each do |league_id, raw_league|
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
              create_or_update_bet(bookmaker_event, 0, 'ML1', nil, raw_event[:moneyline][:_1])
              create_or_update_bet(bookmaker_event, 0, 'ML2', nil, raw_event[:moneyline][:_2])
            end
            # totals
            if raw_event[:totals]
              raw_event[:totals].each do |t|
                create_or_update_bet(bookmaker_event, 0, 'TO', t[:total], t[:over])
                create_or_update_bet(bookmaker_event, 0, 'TU', t[:total], t[:under])
              end
            end
            # handicaps
            if raw_event[:handicaps]
              raw_event[:handicaps].each do |h|
                create_or_update_bet(bookmaker_event, 0, 'F1', h[:hand_1], h[:odds_1])
                create_or_update_bet(bookmaker_event, 0, 'F2', h[:hand_2], h[:odds_2])
              end
            end
            # odd/even
            if raw_event[:odd_even]
              create_or_update_bet(bookmaker_event, 0, 'ODD', nil, raw_event[:odd_even][:odd])
              create_or_update_bet(bookmaker_event, 0, 'EVEN', nil, raw_event[:odd_even][:even])
            end
            rescan_event(bookmaker_event)
          end
        end
      end

      private

      def parse_money_line(bets_data)
        (moneyline = bets_data.find{ |b| b[1][0] == 11 }) ? { _1: moneyline[2][0], _2: moneyline[2][1] } : {}
      end

    end
  end
end