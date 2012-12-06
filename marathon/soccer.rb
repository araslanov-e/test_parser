module Providers
  class Marathon < Base
    module Soccer

      def parse(page)
        # gathering leagues and events with basic lines
        @league_events = {}
        page.search("div.main-block-events").each do |league_node|
          sport_name, league_name = league_node.at("div.block-events-head").try{ |n| n.content.gsub(/\t/, '').split("\r\n")[4].split(/\.\s*/, 2).map(&:strip) }
          next unless (@bookmaker_sport.name == sport_name)

          league_identifier = league_node[:id].gsub(/[^\d]/, '')

          # try to find or create  bookmaker league
          @bookmaker_league = create_bookmaker_league(league_name, league_identifier)
          @bookmaker_events = bookmaker_events(@bookmaker_league)

          @league_events[league_identifier] ||= { league: @bookmaker_league, events: [] }

          league_node.search("table.foot-market tr.event-header").each do |event_node|
            teams = event_node.search("td.first td[@class$=name] .command div").collect{ |t| t.try{ |n| n.content.strip } }
            next unless teams.any?

            raw_event_id = event_node.at("td.first td.more-view a.event-more-view")['treeid'] rescue nil
            event_date = event_node.at("td.first td.date").try{ |n| n.content.strip }

            # check teams first
            home_team = create_bookmaker_team(teams[0].strip)
            away_team = create_bookmaker_team(teams[1].strip)

            # creating events
            Time.zone = @time_zone
            event_time = Time.zone.parse(event_date)
            bookmaker_event = create_bookmaker_event(home_team, away_team, event_time)



            # 1 X 2 1X 12 X2 hand_1 hand_2 under over
            _, _1, _x, _2, _1x, _12, _x2, _f1, _f2, under, over = event_node.search('./td').map{ |node| node }

            hand_1 = parse_node(_f1, true); odds_1 = parse_node(_f1)
            hand_2 = parse_node(_f2, true); odds_2 = parse_node(_f2)
            _1 = parse_node(_1); _x = parse_node(_x); _2 = parse_node(_2)
            _1x = parse_node(_1x); _12 = parse_node(_12); _x2 = parse_node(_x2)
            total = parse_node(over, true) || parse_node(under, true); under = parse_node(under); over = parse_node(over)

            # check if event is changed
            next if @updates_only and
                not bookmaker_event_changed?(bookmaker_event, [0, nil, nil, hand_1, odds_1, hand_2, odds_2, _1, _x, _2, _1x, _12, _x2, total, under, over])

            event = {
              bookmaker_event: bookmaker_event,
              raw_event_id: raw_event_id,
              url: raw_event_id ? URL_ADDITIONAL_LINES % raw_event_id : nil
            }

            # moneylines
            event[:moneylines] = [{ period: 0, _1: _1, _x: _x, _2: _2 }]
            # double chances
            event[:doublechances] = [{ period: 0, _1x: _1x, _12: _12, _x2: _x2 }]
            # handicaps
            event[:handicaps] = [{ period: 0, hand_1: hand_1, odds_1: odds_1, hand_2: hand_2, odds_2: odds_2 }]
            # totals
            event[:totals] = [{ period: 0, total: total, over: over, under: under }]

            @league_events[league_identifier][:events] << event
          end
        end

        threads = []
        # gathering additional lines
        @league_events.each_value do |league|
          league[:events].each do |event|
            next unless event[:url]

            threads << Thread.new(event) do |evt|
              sleep(rand(10)) # timeout, for other sports is 10

              begin
                page_json = JSON.parse(open_uri(evt[:url], read_timeout: 5, proxy: @current_proxy).read)
              rescue Exception => e
                logger.error("Error requesting data on #{evt[:url]}: #{e.message}")
                Thread.current.kill
              end

              unless (page = Nokogiri::HTML(page_json['HTML']))
                logger.error("Error parsing HTML on #{evt[:url]}")
                Thread.current.kill
              end

              # 1st/2nd period basic line
              %w{ 1st 2nd }.each_with_index do |half, i|
                period = i + 1
                half_line_node = page.at("tr[@class^=market-details] td.first-r-short[contains('#{half} Half')]").try{ |n| n.parent.search('td.b-none') }
                if half_line_node
                  _, _1, _x, _2, _1x, _12, _x2, _f1, _f2, under, over = half_line_node
                  # moneyline
                  evt[:moneylines] << { period: period, _1: parse_node(_1), _x: parse_node(_x), _2: parse_node(_2) }
                  # double chance
                  evt[:doublechances] << { period: period, _1x: parse_node(_1x), _12: parse_node(_12), _x2: parse_node(_x2) }
                  # handicaps
                  evt[:handicaps] << {
                      period: period,
                      hand_1: parse_node(_f1, true),
                      odds_1: parse_node(_f1),
                      hand_2: parse_node(_f2, true),
                      odds_2: parse_node(_f2)
                  }
                  # totals
                  evt[:totals] << {
                      period: period,
                      total: parse_node(over, true) || parse_node(under, true),
                      over: parse_node(over),
                      under: parse_node(under)
                  }
                end
              end
              # totals, asian totals
              %w{ 9 10 12 13 454332198 }.each do |line_number|
                #total_lines = page.search("div[id$=marketId#{line_number}] table.td-border tr")
                total_lines = page.search("div[id$=event#{evt[:raw_event_id]}block3marketId#{line_number}] table.td-border tr")
                unless total_lines.blank?
                  totals = total_lines[0].search('th')
                  unders = total_lines[1].search('td')
                  overs = total_lines[2].search('td')

                  period = case line_number
                    when '13' then 2
                    when '12' then 1
                    else 0
                  end
                  totals[1..-1].each_with_index do |node, i|
                    total = node.try{ |n| n.content.strip }
                    evt[:totals] << {
                        period: period,
                        total: total,
                        over: parse_node(overs[i + 1]),
                        under: parse_node(unders[i + 1])
                    } unless evt[:totals].find{ |t| t[:period] == period and t[:total] == total }
                  end
                end
              end
              # handicaps, asian handicaps, 1st/2nd period handicaps
              %w{ 4 5 7 8 }.each do |line_number|
                #hand_lines = page.search("div[id$=marketId#{line_number}] table.td-border tr")
                hand_lines = page.search("div[id$=event#{evt[:raw_event_id]}block2marketId#{line_number}] table.td-border tr")

                unless hand_lines.blank?
                  home_team_hands = hand_lines[0].search('td')
                  away_team_hands = hand_lines[1].search('td')

                  period = case line_number
                    when '8' then 2
                    when '7' then 1
                    else 0
                  end
                  home_team_hands[1..-1].each_with_index do |node, i|
                    hand_1 = parse_node(node, true)
                    evt[:handicaps] << {
                        period: period,
                        hand_1: hand_1,
                        odds_1: parse_node(node),
                        hand_2: parse_node(away_team_hands[i + 1], true),
                        odds_2: parse_node(away_team_hands[i + 1])
                    } unless evt[:handicaps].find{ |h| h[:period] == period and h[:hand_1] == hand_1 }
                  end
                end
              end
              evt[:ind_totals] ||= { home_team: [], away_team: [] }
              %w{ 27 28 }.each do |line_number|
                ind_total_lines = page.search("div[id$=event#{evt[:raw_event_id]}block3marketId#{line_number}] table.td-border tr")
                unless ind_total_lines.blank?
                  totals = ind_total_lines[0].search('th')
                  unders = ind_total_lines[1].search('td')
                  overs = ind_total_lines[2].search('td')

                  totals[1..-1].each_with_index do |node, i|
                    total = node.try{ |n| n.content.strip }
                    if line_number == '27'
                      evt[:ind_totals][:home_team] << { total: total, over: parse_node(overs[i + 1]), under: parse_node(unders[i + 1]) }
                    elsif line_number == '28'
                      evt[:ind_totals][:away_team] << { total: total, over: parse_node(overs[i + 1]), under: parse_node(unders[i + 1]) }
                    end
                  end
                end
              end
            end
            # process 30 tasks in a row
            if threads.length >= 30
              threads.map(&:join)
              threads.clear
            end
          end
        end
        threads.map(&:join)

        @league_events.each_value do |league|
          league[:events].each do |raw_event|
            bookmaker_event = raw_event[:bookmaker_event]

            # bookmaker's bet
            @bets = bookmaker_event.bets
            @bets_to_remove[bookmaker_event.id] = @bets.map(&:id) unless @bets_to_remove[bookmaker_event.id]

            # moneylines
            unless raw_event[:moneylines].blank?
              raw_event[:moneylines].each do |m|
                create_or_update_bet(bookmaker_event, m[:period], '1', nil, m[:_1])
                create_or_update_bet(bookmaker_event, m[:period], 'X', nil, m[:_x])
                create_or_update_bet(bookmaker_event, m[:period], '2', nil, m[:_2])
              end
            end
            # double chances
            unless raw_event[:doublechances].blank?
              raw_event[:doublechances].each do |d|
                create_or_update_bet(bookmaker_event, d[:period], '1X', nil, d[:_1x])
                create_or_update_bet(bookmaker_event, d[:period], '12', nil, d[:_12])
                create_or_update_bet(bookmaker_event, d[:period], 'X2', nil, d[:_x2])
              end
            end
            # totals
            unless raw_event[:totals].blank?
              raw_event[:totals].each do |t|
                create_or_update_bet(bookmaker_event, t[:period], 'TO', t[:total], t[:over])
                create_or_update_bet(bookmaker_event, t[:period], 'TU', t[:total], t[:under])
              end
            end
            # handicaps
            unless raw_event[:handicaps].blank?
              raw_event[:handicaps].each do |h|
                create_or_update_bet(bookmaker_event, h[:period], 'F1', h[:hand_1], h[:odds_1])
                create_or_update_bet(bookmaker_event, h[:period], 'F2', h[:hand_2], h[:odds_2])
              end
            end
            # individual totals
            unless raw_event[:ind_totals].blank?
              # home team
              raw_event[:ind_totals][:home_team].each do |t|
                create_or_update_bet(bookmaker_event, 0, 'I1TO', t[:total], t[:over]) if t[:over]
                create_or_update_bet(bookmaker_event, 0, 'I1TU', t[:total], t[:under]) if t[:under]
              end
              # away team
              raw_event[:ind_totals][:away_team].each do |t|
                create_or_update_bet(bookmaker_event, 0, 'I2TO', t[:total], t[:over]) if t[:over]
                create_or_update_bet(bookmaker_event, 0, 'I2TU', t[:total], t[:under]) if t[:under]
              end
            end
            rescan_event(bookmaker_event)
          end
        end
      end

    end
  end
end