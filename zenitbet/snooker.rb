# encoding: UTF-8
module Providers
  class Zenitbet < Base
    module Snooker

      def parse(page)
        page.search("div.b-league[id^=lid]").each do |league_node|
          title_node = league_node.at('div.b-league-name span.b-league-name-label')
          sport_name, league_name = title_node.content.split(/\.\s*/, 2)

          league_identifier = league_node.at("div.b-league-name.h-league")["data-lid"]

          # try to find bookmaker sport
          next unless (bookmaker_sport.name == sport_name)
          next if league_name =~ /Статистические данные|goals|special|extra bets|all\-stars weekend/i

          # try to find or create bookmaker league
          @bookmaker_league = create_bookmaker_league(league_name, league_identifier)
          @bookmaker_events = bookmaker_events(@bookmaker_league)

          league_node.search('tr[id^=gid]').each do |event_node|
            event_id = event_node.attr("id").gsub(/gid/, "")
            next if event_id =~ /ross/

            basic_line = event_node.search('./td').map{ |node| node.content.gsub(/,/, '.').strip }
            event_raw_date, teams, _ml1, _, _ml2, _, _, _, _, _, _, _, _, _, _ = basic_line
            #puts basic_line.join(' : ')

            team_1, team_2 = teams.split(' - ', 2)
            team_2.gsub!(/ Нейтральное поле/, "")

            next unless (team_1 and team_2)

            # check teams first
            home_team = create_bookmaker_team(team_1)
            away_team = create_bookmaker_team(team_2)

            # creating events
            Time.zone = @time_zone
            event_time = Time.strptime("#{event_raw_date}", '%d/%m %H:%M').strftime("%Y-%m-%d %H:%M")
            event_time = Time.zone.parse("#{event_time}")
            bookmaker_event = create_bookmaker_event(home_team, away_team, event_time)



            # bookmaker's bet
            @bets = bookmaker_event.bets
            @bets_to_remove[bookmaker_event.id] = @bets.map(&:id) unless @bets_to_remove[bookmaker_event.id]

            # basic line
            create_or_update_bet(bookmaker_event, 0, 'ML1', nil, _ml1)
            create_or_update_bet(bookmaker_event, 0, 'ML2', nil, _ml2)

            rescan_event(bookmaker_event)
          end
        end
      end
    end
  end
end