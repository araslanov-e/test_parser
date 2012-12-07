module Providers
  class Example < Base
    module Soccer

      def parse(doc)
        doc.css('leagues league').each do |league|
          league.css('events event').each do |raw_event|
            home_team_name = raw_event.at_css('homeTeam name').content
            away_team_name = raw_event.at_css('awayTeam name').content

            puts "#{home_team_name} - #{away_team_name}"

            event_time = Time.parse(raw_event.at_css('startDateTime').content)

            raw_event.css('periods period').each do |period|
              number = period.css('number').first.content
              # spreads
              period.css('spreads spread').each do |spread|
                # home
                puts "#{number}, 'F1', #{spread.at_css('homeSpread').content}, #{spread.at_css('homePrice').content}"
                # away
                puts "#{number}, 'F2', #{spread.at_css('awaySpread').content}, #{spread.at_css('awayPrice').content}"
              end
              # totals
              period.css('totals total').each do |total|
                points = total.at_css('points').content
                # over
                puts "#{number}, 'TO', #{points}, #{total.at_css('overPrice').content}"
                # under
                puts "#{number}, 'TU', #{points}, #{total.at_css('underPrice').content}"
              end
              # moneyline
              unless (money_line = period.xpath('./moneyLine')).empty?
                # home
                puts "#{number}, '1', nil, #{money_line.at_css('homePrice').content}"
                # draw
                puts "#{number}, 'X', nil, #{money_line.at_css('drawPrice').content}"
                # away
                puts "#{number}, '2', nil, #{money_line.at_css('awayPrice').content}"
              end
              # team totals
              unless (team_totals = period.xpath('./teamTotals')).empty?
                # home
                unless (home_team_total = team_totals.xpath('./homeTeamTotal')).empty?
                  points = home_team_total.at_css('total').content
                  # over
                  puts "#{number}, 'I1TO', #{points}, #{home_team_total.at_css('overPrice').content}"
                  # under
                  puts "#{number}, 'I1TU', #{points}, #{home_team_total.at_css('underPrice').content}"
                end
                # away
                unless (away_team_total = team_totals.xpath('./awayTeamTotal')).empty?
                  points = away_team_total.at_css('total').content
                  # over
                  puts "#{number}, 'I2TO', #{points}, #{away_team_total.at_css('overPrice').content}"
                  # under
                  puts "#{number}, 'I2TU', #{points}, #{away_team_total.at_css('underPrice').content}"
                end
              end
            end

          end
        end
      end

    end
  end
end