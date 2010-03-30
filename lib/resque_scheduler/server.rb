# Extend Resque::Server to add tabs
module ResqueScheduler
  
  module Server
        
    def self.included(base)

      base.class_eval do
        
        helpers do
          def format_time(t)
            t.strftime("%Y-%m-%d %H:%M:%S")
          end

          def queue_from_class_name(class_name)
            Resque.queue_from_class(Resque.constantize(class_name))
          end
          
          def distance_of_time_in_words(from_time, to_time = 0, include_seconds = false)
            from_time = from_time.to_time if from_time.respond_to?(:to_time)
            to_time = to_time.to_time if to_time.respond_to?(:to_time)
            distance_in_minutes = (((to_time - from_time).abs)/60).round
            distance_in_seconds = ((to_time - from_time).abs).round

            case distance_in_minutes
              when 0..1
                return (distance_in_minutes == 0) ? 'less than a minute' : '1 minute' unless include_seconds
                case distance_in_seconds
                  when 0..4   then 'less than 5 seconds'
                  when 5..9   then 'less than 10 seconds'
                  when 10..19 then 'less than 20 seconds'
                  when 20..39 then 'half a minute'
                  when 40..59 then 'less than a minute'
                  else             '1 minute'
                end

              when 2..44           then "#{distance_in_minutes} minutes"
              when 45..89          then 'about 1 hour'
              when 90..1439        then "about #{(distance_in_minutes.to_f / 60.0).round} hours"
              when 1440..2879      then '1 day'
              when 2880..43199     then "#{(distance_in_minutes / 1440).round} days"
              when 43200..86399    then 'about 1 month'
              when 86400..525599   then "#{(distance_in_minutes / 43200).round} months"
              when 525600..1051199 then 'about 1 year'
              else                      "over #{(distance_in_minutes / 525600).round} years"
            end
          end
        end
        
        require 'active_support'
        
        get "/schedule" do
          # Is there a better way to specify alternate template locations with sinatra?
          erb File.read(File.join(File.dirname(__FILE__), 'server/views/scheduler.erb'))
        end

        post "/schedule/requeue" do
          config = Resque.schedule[params['job_name']]
          Resque::Scheduler.enqueue_from_config(config)
          redirect url("/overview")
        end
        
        get "/processes" do
          erb File.read(File.join(File.dirname(__FILE__), 'server/views/processes.erb'))
        end
        
        get "/delayed" do
          # Is there a better way to specify alternate template locations with sinatra?
          erb File.read(File.join(File.dirname(__FILE__), 'server/views/delayed.erb'))
        end

        get "/delayed/:timestamp" do
          # Is there a better way to specify alternate template locations with sinatra?
          erb File.read(File.join(File.dirname(__FILE__), 'server/views/delayed_timestamp.erb'))
        end

      end

    end

    Resque::Server.tabs << 'Schedule'
    Resque::Server.tabs << 'Delayed'
    Resque::Server.tabs << 'Processes'

  end
  
end