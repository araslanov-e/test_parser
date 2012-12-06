# encoding: UTF-8
module Providers
  class Zenitbet < Base
    module Tennis

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

            period = -1

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
            # handicap 1
            create_or_update_bet(bookmaker_event, period, 'F1', hand_1, odds_1)
            # handicap 2
            create_or_update_bet(bookmaker_event, period, 'F2', hand_2, odds_2)
            # first team win
            create_or_update_bet(bookmaker_event, period, 'ML1', nil, _ml1)
            # second team win
            create_or_update_bet(bookmaker_event, period, 'ML2', nil, _ml2)
            # totals
            create_or_update_bet(bookmaker_event, period, 'TO', total, over)
            create_or_update_bet(bookmaker_event, period, 'TU', total, under)

            add_lines_node = league_node.at("tr[@id=gid-ross#{event_id}]")
            if add_lines_node
              add_lines_node.search("td div div").each do |line|

                # spreads
                if line.content =~ /Дополнительные форы:/
                  team_1_spreads, team_2_spreads = line.content.gsub(/Дополнительные форы: #{team_1}: фора матча/, "").split("#{team_2}: фора матча ").map(&:strip)
                  team_1_spreads.split("; ").each do |spread|
                    m = spread.match(/\(([\d\.\-\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, period, "F1", m[1], m[2].gsub(/,/, '.')) if m
                  end
                  team_2_spreads.split("; ").each do |spread|
                    m = spread.match(/\(([\d\.\-\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, period, "F2", m[1], m[2].gsub(/,/, '.')) if m
                  end
                end

                # totals
                if line.content =~ /Дополнительные тоталы:/
                  unders, overs = line.content.gsub(/Дополнительные тоталы: меньше/, "").split("больше").map(&:strip)
                  unders.split("; ").each do |total_under|
                    m = total_under.match(/\(([\d\.\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, period, "TU", m[1], m[2].gsub(/,/, '.')) if m
                  end
                  overs.split("; ").each do |total_over|
                    m = total_over.match(/\(([\d\.\,]+)\) - ([\d\.\,]+)/)
                    create_or_update_bet(bookmaker_event, period, "TO", m[1], m[2].gsub(/,/, '.')) if m
                  end
                end

              end

              # set outcome
              if (set_outcome_node = add_lines_node.at('table'))

                set_outcome_node.search("tr").each do |tr|
                  _line = tr.search('./td').map{ |node| node.content.gsub(/,/, '.').strip }
                  next unless _line.size > 0
                  case _line.size
                    when 10 #  # П1	П2	Ф1	Кф1	Ф2	Кф2	Мен	Тот	Бол
                      period, _ml1, _ml2, hand_1, odds_1, hand_2, odds_2, under_1, total_1, over_1 = _line
                    when 6 #  # П1	П2	Мен	Тот	Бол
                      period, _ml1, _ml2, under_1, total_1, over_1 = _line
                    else
                      period, hand_1, odds_1, hand_2, odds_2, under_1, total_1, over_1 = _line
                  end
                  period.gsub!(/\D/, "")

                  if _line.size == 10 or _line.size == 6
                    # first team win
                    create_or_update_bet(bookmaker_event, period, 'ML1', nil, _ml1)
                    # second team win
                    create_or_update_bet(bookmaker_event, period, 'ML2', nil, _ml2)
                  end
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
            end
            rescan_event(bookmaker_event)
          end
        end
      end
    end
  end
end