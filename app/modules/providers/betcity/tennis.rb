module Providers
  class Betcity < Base
    module Tennis

      def parse(page)
        page.search('//table/thead').each do |league_node|
          parent_node = league_node.parent

          league_identifier = league_node.at('a')[:name].gsub(/[^\d]/, '')
          sport_name, league_name = league_node.content.split(/\.\s*/, 2)

          # try to find bookmaker sport
          #next unless sport_name.match(Regexp.new(bookmaker_sport.name)) # can be Tennis Grand Slam
          next unless (bookmaker_sport.name == sport_name)

          next if league_name =~ /statistics|goals|special|extra bets|all\-stars weekend/i

          # try to find or create bookmaker league
          @bookmaker_league = create_bookmaker_league(league_name, league_identifier)
          @bookmaker_events = bookmaker_events(@bookmaker_league)

          event_raw_date = nil
          header_line = nil
          parent_node.search('./tbody').each do |event_node|
            event_raw_date = event_node.content if event_node[:class] == 'date'
            header_line = event_node.at('tr[@class=th]').search('./td').map{ |node| node.content.strip } if event_node[:class] == 'chead'
            next unless event_node[:id] == 'line'

            basic_line_node = event_node.at('tr[@class^=tc]')
            next unless basic_line_node

            basic_line = basic_line_node.search('./td').map{ |node| {content: node.content.strip, link: (node.at('a')['href'].gsub(/\/left\.php\?bb\=/, '') rescue nil) }}

            if header_line[2] != 'Handicap'
              hand_1 = odds_1 = hand_2 = odds_2 = total = under = over = nil
              event_raw_time, team_1, team_2, ml_1, ml_2 = basic_line
            else
              event_raw_time, team_1, hand_1, odds_1, team_2, hand_2, odds_2, total, under, over, ml_1, ml_2 = basic_line
            end

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
            #    not bookmaker_event_changed?(bookmaker_event, [-1, ml_1[:content], ml_2[:content], hand_1[:content], odds_1[:content], hand_2[:content], odds_2[:content], nil, nil, nil, nil, nil, nil, total[:content], under[:content], over[:content]])

            # bookmaker's bet
            @bets = bookmaker_event.bets
            @bets_to_remove[bookmaker_event.id] = @bets.map(&:id) unless @bets_to_remove[bookmaker_event.id]

            # basic line
            parse_baseline(bookmaker_event, -1, [ml_1, ml_2], nil, nil, [hand_1, odds_1], [hand_2, odds_2], [[total, under, over]], nil, nil)

            # additional lines
            add_lines_nodes = event_node.search('./tr[starts-with(@id, "tr")]/td')
            next unless add_lines_nodes
            # Player's total games won: Wozniacki C.: (12.5) Under 1.55; Over 2.3; Radwanska U.: (8.5) Under 1.85; Over 1.85;
            # ind total
            add_lines_nodes.search('./div[b="Player\'s total games won:"]').each do |it|
              total_1, under_1, over_1, total_2, under_2, over_2 = parse_ind_total(it.content, team_1[:content], team_2[:content])
              # ind total 1
              if total_1
                create_or_update_bet(bookmaker_event, -1, 'I1TU', total_1, under_1) if under_1
                create_or_update_bet(bookmaker_event, -1, 'I1TO', total_1, over_1) if over_1
              end
              # ind total 2
              if total_2
                create_or_update_bet(bookmaker_event, -1, 'I2TU', total_2, under_2) if under_2
                create_or_update_bet(bookmaker_event, -1, 'I2TO', total_2, over_2) if over_2
              end
            end
            # handicaps
            add_lines_nodes.search('./div[b="Handicap:"]').each do |h|
              _team_1, hand_1, value_1, _team_2, hand_2, value_2 = parse_handicaps(h.content, team_1[:content], team_2[:content])
              # handicap 1
              create_or_update_bet(bookmaker_event, -1, 'F1', hand_1, value_1) if hand_1 and value_1
              # handicap 2
              create_or_update_bet(bookmaker_event, -1, 'F2', hand_2, value_2) if hand_2 and value_2
            end
            # totals
            add_lines_nodes.search('./div[b="Total:"]').each do |t|
              total, under, over = parse_totals(t.content)
              if total # notice: totals can be the same as in the basic line
                create_or_update_bet(bookmaker_event, -1, 'TU', total, under) if under
                create_or_update_bet(bookmaker_event, -1, 'TO', total, over) if over
              end
            end
            # total sets
            add_lines_nodes.search('./div[b="Total sets:"]').each do |t|
              total, under, over = parse_totals(t.content)
              if total # notice: totals can be the same as in the basic line
                create_or_update_bet(bookmaker_event, -1, 'SET_TU', total, under) if under
                create_or_update_bet(bookmaker_event, -1, 'SET_TO', total, over) if over
              end
            end
            # sets handicap
            add_lines_nodes.search('./div[b="Sets handicap:"]').each do |h|
              _team_1, hand_1, value_1, _team_2, hand_2, value_2 = parse_set_handicaps(h.content, team_1[:content], team_2[:content])
              # handicap 1
              create_or_update_bet(bookmaker_event, -1, 'SET_F1', hand_1, value_1) if hand_1 and value_1
              # handicap 2
              create_or_update_bet(bookmaker_event, -1, 'SET_F2', hand_2, value_2) if hand_2 and value_2
            end
            # sets outcome
            if (sets_outcome_node = add_lines_nodes.at('./table[@id="dt"]'))
              %w{1st 2nd 3rd 4th}.each_with_index do |set, i|
                period = i + 1
                set_line = sets_outcome_node.search("./tr[td='#{set} set']/td").map{ |node| {content: node.content.strip, link: (node.at('a')['href'].gsub(/\/left\.php\?bb\=/, '') rescue nil) }}
                _, ml_1, ml_2, hand_1, odds_1, hand_2, odds_2, total_1, under_1, over_1, total_2, under_2, over_2 = set_line

                parse_baseline(bookmaker_event, period, [ml_1, ml_2], nil, nil, [hand_1, odds_1], [hand_2, odds_2], [[total_1, under_1, over_1], [total_2, under_2, over_2]], nil, nil)
              end
            end
            #puts "\n\n"
            rescan_event(bookmaker_event)
          end
        end
      end

      private

      def parse_totals(line)
        # Total: (20.5) Under 2.6; Over 1.49;
        # Total sets: (2.5) Under 1.17; Over 4.4;
        total_matches = line.match(/Total( sets)?:\s\(([\d\.]+)\)\s?(Under\s([\d\.]+);)?\s?(Over\s([\d\.]+);)?/)
        total_matches ? [total_matches[2], total_matches[4], total_matches[6]] : [nil] * 3
      end

      def parse_set_handicaps(line, team_1, team_2)
        team_1_matches = line.match(/Sets handicap:\s?#{Regexp.escape(team_1)}:\s\(([\+\-\d\.]+)\)\s([\d\.]+)/)
        hand_1, value_1 = team_1_matches ? [team_1_matches[1], team_1_matches[2]] : [nil] * 2

        team_2_matches = line.match(/[:;]\s?#{Regexp.escape(team_2)}:\s\(([\+\-\d\.]+)\)\s([\d\.]+)/)
        hand_2, value_2 = team_2_matches ? [team_2_matches[1], team_2_matches[2]] : [nil] * 2

        [team_1, hand_1, value_1, team_2, hand_2, value_2]
      end

      def parse_ind_total(line, team_1, team_2)
        team_1_matches = line.match(/Player\'s total games won:\s#{Regexp.escape(team_1)}:\s\(([\+\-\d\.]+)\)\sUnder\s([\d\.]+);\sOver\s([\d\.]+)/)
        total_1, under_1, over_1 = team_1_matches ? [team_1_matches[1], team_1_matches[2], team_1_matches[3]] : [nil] * 3

        team_2_matches = line.match(/[:;]\s#{Regexp.escape(team_2)}:\s\(([\+\-\d\.]+)\)\sUnder\s([\d\.]+);\sOver\s([\d\.]+);/)
        total_2, under_2, over_2 = team_2_matches ? [team_2_matches[1], team_2_matches[2], team_2_matches[3]] : [nil] * 3

        [total_1, under_1, over_1, total_2, under_2, over_2]
      end
    end
  end
end