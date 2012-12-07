module Providers
  class Example_1 < Base
    module Soccer

      def parse(page)
        page.search('//table/thead').each do |league_node|

          parent_node.search('./tbody').each do |event_node|

            basic_line = basic_line_node.search('./td').map{ |node| {content: node.content.strip, link: (node.at('a')['href'].gsub(/\/left\.php\?bb\=/, '') rescue nil) }}
            event_raw_time, team_1, hand_1, odds_1, team_2, hand_2, odds_2, _1, _x, _2, _1x, _12, _x2, total, under, over = basic_line
            puts basic_line.join(' : ')

            # handicaps
            add_lines_nodes.search('./div[b="Handicap:"]').each do |h|
              _team_1, hand_1, value_1, _team_2, hand_2, value_2 = parse_handicaps(h.content, team_1[:content], team_2[:content])
              #puts "#{_team_1} : #{hand_1} : #{value_1} : #{_team_2} : #{hand_2} : #{value_2}"
            end
            # totals
            add_lines_nodes.search('./div[b="Total:"]').each do |t|
              total, under, over = parse_totals(t.content)
              #puts "#{total} : #{under} : #{over}"
            end
          end
        end
      end
    
    end
  end
end