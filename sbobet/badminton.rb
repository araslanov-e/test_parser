module Providers
  class Sbobet < Base
    module Badminton

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

            # handicaps
            if raw_event[:handicaps]
              raw_event[:handicaps].each do |h|
                create_or_update_bet(bookmaker_event, 0, 'F1', h[:hand_1], h[:odds_1])
                create_or_update_bet(bookmaker_event, 0, 'F2', h[:hand_2], h[:odds_2])
              end
            end
            rescan_event(bookmaker_event)
          end
        end
      end

      private

      def parse_money_line(bets_data); {}; end

    end
  end
end