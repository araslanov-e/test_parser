module Providers
  class Betcity < Base
    module Soccer

      def parse(page)
        page.search('//table/thead').each do |league_node|
          parent_node = league_node.parent

          league_identifier = league_node.at('a')[:name].gsub(/[^\d]/, '')
          sport_name, league_name = league_node.content.split(/\.\s*/, 2)

          # try to find bookmaker sport
          next unless (bookmaker_sport.name == sport_name)

          next if league_name =~ /statistic|goals|special|extra bets|all\-stars weekend/i

          # try to find or create bookmaker league
          @bookmaker_league = create_bookmaker_league(league_name, league_identifier)
          @bookmaker_events = bookmaker_events(@bookmaker_league)

          event_raw_date = nil
          parent_node.search('./tbody').each do |event_node|
            event_raw_date = event_node.content if event_node[:class] == 'date'
            next unless event_node[:id] == 'line'

            basic_line_node = event_node.at('tr[@class^=tc]')
            next unless basic_line_node

            basic_line = basic_line_node.search('./td').map{ |node| {content: node.content.strip, link: (node.at('a')['href'].gsub(/\/left\.php\?bb\=/, '') rescue nil) }}
            event_raw_time, team_1, hand_1, odds_1, team_2, hand_2, odds_2, _1, _x, _2, _1x, _12, _x2, total, under, over = basic_line
            #puts basic_line.join(' : ')

            # check teams first
            home_team = create_bookmaker_team(team_1[:content])
            away_team = create_bookmaker_team(team_2[:content])

            # creating events
            Time.zone = @time_zone
            event_time = Time.zone.parse("#{event_raw_date} #{event_raw_time[:content]}")
            bookmaker_event = create_bookmaker_event(home_team, away_team, event_time, league_identifier)



            # check if event is changed
            # TODO: refactor
            #next if @updates_only and
            #    not bookmaker_event_changed?(bookmaker_event, [0, nil, nil, hand_1[:content], odds_1[:content], hand_2[:content], odds_2[:content], _1[:content], _x[:content], _2[:content], _1x[:content], _12[:content], _x2[:content], total[:content], under[:content], over[:content]])

            # bookmaker's bet
            @bets = bookmaker_event.bets
            @bets_to_remove[bookmaker_event.id] = @bets.map(&:id) unless @bets_to_remove[bookmaker_event.id]

            # basic line
            parse_baseline(bookmaker_event, 0, nil, [_1, _x, _2], [_1x, _12, _x2], [hand_1, odds_1], [hand_2, odds_2], [[total, under, over]], nil, nil)

            # additional lines
            add_lines_nodes = event_node.search('./tr[starts-with(@id, "tr")]/td')
            next unless add_lines_nodes

            # handicaps
            add_lines_nodes.search('./div[b="Handicap:"]').each do |h|
              _team_1, hand_1, value_1, _team_2, hand_2, value_2 = parse_handicaps(h.content, team_1[:content], team_2[:content])
              #puts "#{_team_1} : #{hand_1} : #{value_1} : #{_team_2} : #{hand_2} : #{value_2}"
              # handicap 1
              create_or_update_bet(bookmaker_event, 0, 'F1', hand_1, value_1) if hand_1 and value_1
              # handicap 2
              create_or_update_bet(bookmaker_event, 0, 'F2', hand_2, value_2) if hand_2 and value_2
            end
            # totals
            add_lines_nodes.search('./div[b="Total:"]').each do |t|
              total, under, over = parse_totals(t.content)
              #puts "#{total} : #{under} : #{over}"
              if total # notice: totals can be the same as in the basic line
                create_or_update_bet(bookmaker_event, 0, 'TU', total, under) if under
                create_or_update_bet(bookmaker_event, 0, 'TO', total, over) if over
              end
            end
            # both to score
            add_lines_nodes.search('./div[b="Both teams to score or one scoreless:"]').each do |bts|
              bts_matches = bts.content.match(/Both score:\s([\d\.]+); One scoreless:\s([\d\.]+)/)
              bts_y_value, bts_n_value = bts_matches ? [bts_matches[1], bts_matches[2]] : nil * 2
              create_or_update_bet(bookmaker_event, 0, 'BTS_Y', nil, bts_y_value) if bts_y_value
              create_or_update_bet(bookmaker_event, 0, 'BTS_N', nil, bts_n_value) if bts_n_value
            end
            # even/odd
            add_lines_nodes.search('./div[b="Even/Odd Total:"]').each do |event_odd|
              event_odd_matches = event_odd.content.match(/Even:\s([\d\.]+); Odd:\s([\d\.]+)/)
              even_value, odd_value = event_odd_matches ? [event_odd_matches[1], event_odd_matches[2]] : nil * 2
              create_or_update_bet(bookmaker_event, 0, 'EVEN', nil, even_value) if even_value
              create_or_update_bet(bookmaker_event, 0, 'ODD', nil, odd_value) if odd_value
            end
            # individual totals
            add_lines_nodes.search('./div[b="Ind. Total:"]').each do |it|
              _team_1, total_1, under_1, over_1, _team_2, total_2, under_2, over_2 = parse_ind_totals(it.content, team_1[:content], team_2[:content])
              #puts "#{_team_1} : #{total_1} : #{under_1} : #{over_1} : #{_team_2} : #{total_2} : #{under_2} : #{over_2}"
              # team 1
              if total_1
                create_or_update_bet(bookmaker_event, 0, 'I1TU', total_1, under_1) if under_1
                create_or_update_bet(bookmaker_event, 0, 'I1TO', total_1, over_1) if over_1
              end
              # team 2
              if total_2
                create_or_update_bet(bookmaker_event, 0, 'I2TU', total_2, under_2) if under_2
                create_or_update_bet(bookmaker_event, 0, 'I2TO', total_2, over_2) if over_2
              end
            end
            # halves outcome
            if (halves_outcome_node = add_lines_nodes.at('./table[@id="dt"]'))
              %w{1st 2nd}.each_with_index do |half, i|
                period = i + 1
                half_line = halves_outcome_node.search("./tr[td='#{half} half']/td").map{ |node| {content: node.content.strip, link: (node.at('a')['href'].gsub(/\/left\.php\?bb\=/, '') rescue nil) }}
                _, _1, _x, _2, _1x, _12, _x2, hand_1, odds_1, hand_2, odds_2, total_1, under_1, over_1, total_2, under_2, over_2, total_3, under_3, over_3 = half_line
                #puts half_line.join(' : ')
                parse_baseline(bookmaker_event, period, nil, [_1, _x, _2], [_1x, _12, _x2], [hand_1, odds_1], [hand_2, odds_2], [[total_1, under_1, over_1], [total_2, under_2, over_2], [total_3, under_3, over_3]], nil, nil)
              end
            end
            #puts "\n\n"
            rescan_event(bookmaker_event)
          end
        end
      end
    end
  end
end