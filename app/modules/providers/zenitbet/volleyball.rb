# encoding: UTF-8
module Providers
  class Zenitbet < Base
    module Volleyball

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
            event_raw_date, teams, _ml1, _ml2, hand_1, odds_1, hand_2, odds_2, under, total, over = basic_line
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
            create_or_update_bet(bookmaker_event, 0, 'F1', hand_1, odds_1)
            create_or_update_bet(bookmaker_event, 0, 'F2', hand_2, odds_2)

            create_or_update_bet(bookmaker_event, 0, 'ML1', nil, _ml1)
            create_or_update_bet(bookmaker_event, 0, 'ML2', nil, _ml2)

            create_or_update_bet(bookmaker_event, 0, 'TO', total, over)
            create_or_update_bet(bookmaker_event, 0, 'TU', total, under)

            add_lines_node = league_node.at("tr[@id=gid-ross#{event_id}]")
            if add_lines_node
              # halves outcome
              if (halves_outcome_node = add_lines_node.at('table'))

                halves_outcome_node.search("tr").each do |tr|
                  _line = tr.search('./td').map{ |node| node.content.gsub(/,/, '.').strip }
                  next unless _line.size > 0

                  period, _ml1, _ml2, hand_1, odds_1, hand_2, odds_2, under_1, total_1, over_1 = _line

                  period.gsub!(/\D/, "")

                  # first team win
                  create_or_update_bet(bookmaker_event, period, 'ML1', nil, _ml1)
                  # second team win
                  create_or_update_bet(bookmaker_event, period, 'ML2', nil, _ml2)
                  # handicap 1
                  create_or_update_bet(bookmaker_event, period, 'F1', hand_1, odds_1)
                  # handicap 2
                  create_or_update_bet(bookmaker_event, period, 'F2', hand_2, odds_2)
                  # totals
                  if total_1
                    create_or_update_bet(bookmaker_event, period, 'TO', total_1, over_1)
                    create_or_update_bet(bookmaker_event, period, 'TU', total_1, under_1)
                  end
                end
              end


              add_lines_node.search("td div div").each do |line|

                # spreads
                if line.content =~ /Дополнительные форы:/
                  team_1_spreads, team_2_spreads = line.content.gsub(/Дополнительные форы: #{team_1}: фора матча/, "").split("#{team_2}: фора матча ").map(&:strip)
                   team_1_spreads.split("; ").each do |spread|
                    m = spread.match(/\(([\d\.\-\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, 0, "F1", m[1], m[2].gsub(/,/, '.')) if m
                   end
                  team_2_spreads.split("; ").each do |spread|
                    m = spread.match(/\(([\d\.\-\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, 0, "F2", m[1], m[2].gsub(/,/, '.')) if m
                   end
                end

                # set spreads
                if line.content =~ /Форы по партиям:/
                  team_1_spreads, team_2_spreads = line.content.gsub(/Дополнительные форы: #{team_1}:/, "").split("#{team_2}").map(&:strip)
                  team_1_spreads.split("; ").each do |spread|
                    m = spread.match(/\(([\d\.\-\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, 0, "SET_F1", m[1], m[2].gsub(/,/, '.')) if m
                  end
                  team_2_spreads.split("; ").each do |spread|
                    m = spread.match(/\(([\d\.\-\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, 0, "SET_F2", m[1], m[2].gsub(/,/, '.')) if m
                  end
                end

                # totals
                if line.content =~ /Дополнительные тоталы:/
                  unders, overs = line.content.gsub(/Дополнительные тоталы: меньше/, "").split("больше").map(&:strip)
                  unders.split("; ").each do |total_under|
                    m = total_under.match(/\(([\d\.\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, 0, "TU", m[1], m[2].gsub(/,/, '.')) if m
                  end
                  overs.split("; ").each do |total_over|
                    m = total_over.match(/\(([\d\.\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, 0, "TO", m[1], m[2].gsub(/,/, '.')) if m
                  end
                end

                # ind totals
                [team_1, team_2].each_with_index do |team, i|
                  if line.content =~ /Индивидуальные тоталы: #{team} меньше/
                    unders, overs = line.content.gsub(/Индивидуальные тоталы: #{team} Меньше/, "").split("больше").map(&:strip)
                    unders.split("; ").each do |total_under|
                      m = total_under.match(/\(([\d\.\,]+)\) - ([\d\.\,]+)/)
                      create_or_update_bet(bookmaker_event, 0, "I#{i+1}TU", m[1], m[2].gsub(/,/, '.')) if m
                    end
                    overs.split("; ").each do |total_over|
                      m = total_over.match(/\(([\d\.\,]+)\) - ([\d\.\,]+)/)
                      create_or_update_bet(bookmaker_event, 0, "I#{i+1}TO", m[1], m[2].gsub(/,/, '.')) if m
                    end
                  end
                end
              end
            end
            rescan_event(bookmaker_event)
          end
        end
      end
    end
  end
end