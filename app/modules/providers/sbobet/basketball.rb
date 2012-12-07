module Providers
  class Sbobet < Base
    module Basketball

      def parse
        @league_events.each do |league_id, raw_league|
          quarter_match_pattern = /\s\-\s(1st|2nd|3rd|4th)\sQuarter/
          if (quarter_match = raw_league[:name].match(quarter_match_pattern)) # leagues like WNBA - 1st Quarter
            raw_league[:name].gsub!(quarter_match_pattern, '')
          end

          @bookmaker_league = create_bookmaker_league(raw_league[:name], league_id)
          @bookmaker_events = bookmaker_events(@bookmaker_league)

          raw_league[:events].each_value do |raw_event|
            # check teams first
            team_strip_pattern = /\((n|1st\sQ|2nd\sQ|3rd\sQ|4th\sQ)\)/
            home_team = create_bookmaker_team(raw_event[:home_team].gsub(team_strip_pattern, '')) # remove (n)
            away_team = create_bookmaker_team(raw_event[:away_team].gsub(team_strip_pattern, '')) # remove (n)

            # creating events
            Time.zone = @time_zone
            event_time = Time.zone.parse(raw_event[:event_date].gsub(/^(\d{2})\/(\d{2})(.+)$/, '\2/\1\3'))
            bookmaker_event = create_bookmaker_event(home_team, away_team, event_time, raw_event[:short_url])



            # bookmaker's bet
            @bets = bookmaker_event.bets
            @bets_to_remove[bookmaker_event.id] = @bets.map(&:id) unless @bets_to_remove[bookmaker_event.id]

            quarter = if quarter_match
              case quarter_match[1]
                when '1st' then 1
                when '2nd' then 2
                when '3rd' then 3
                when '4th' then 4
              end
            else; -1; end
            # totals
            if raw_event[:totals]
              raw_event[:totals].each do |t|
                create_or_update_bet(bookmaker_event, quarter, 'TO', t[:total], t[:over])
                create_or_update_bet(bookmaker_event, quarter, 'TU', t[:total], t[:under])
              end
            end
            # 1st half totals (not 1st quarter)
            if raw_event[:_1st_totals]
              raw_event[:_1st_totals].each do |t|
                create_or_update_bet(bookmaker_event, 10, 'TO', t[:total], t[:over])
                create_or_update_bet(bookmaker_event, 10, 'TU', t[:total], t[:under])
              end
            end
            # handicaps
            if raw_event[:handicaps]
              raw_event[:handicaps].each do |h|
                create_or_update_bet(bookmaker_event, quarter, 'F1', h[:hand_1], h[:odds_1])
                create_or_update_bet(bookmaker_event, quarter, 'F2', h[:hand_2], h[:odds_2])
              end
            end
            # 1st handicaps (not 1st quarter)
            if raw_event[:_1st_handicaps]
              raw_event[:_1st_handicaps].each do |h|
                create_or_update_bet(bookmaker_event, 10, 'F1', h[:hand_1], h[:odds_1])
                create_or_update_bet(bookmaker_event, 10, 'F2', h[:hand_2], h[:odds_2])
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

      def parse_money_line(bets_data); {}; end
    end
  end
end