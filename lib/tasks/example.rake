namespace :example do
  namespace :import do

    desc 'Imports soccer lines'
    task soccer: :environment do
      provider = Providers::Example.new(:soccer)
      provider.bet_lines
    end

  end
end
