require 'rubygems'
require 'resque'
require 'resque/server'
require 'resque_scheduler/version'
require 'resque/scheduler'
require 'resque_scheduler/server'

module ResqueScheduler

  #
  # Accepts a new schedule configuration of the form:
  #
  #   {some_name => {"cron" => "5/* * * *",
  #                  "class" => DoSomeWork,
  #                  "args" => "work on this string",
  #                  "description" => "this thing works it"s butter off"},
  #    ...}
  #
  # :name can be anything and is used only to describe the scheduled job
  # :cron can be any cron scheduling string :job can be any resque job class
  # :class must be a resque worker class
  # :args can be any yaml which will be converted to a ruby literal and passed
  #   in a params. (optional)
  # :description is just that, a description of the job (optional). If params is
  #   an array, each element in the array is passed as a separate param,
  #   otherwise params is passed in as the only parameter to perform.
  def schedule=(schedule_hash)
    redis[:resque_schedule_hash] = schedule_hash.to_yaml
  end

  # Returns the schedule hash
  def schedule
    YAML.load(redis[:resque_schedule_hash])
  end

  # This method is nearly identical to +enqueue+ only it also
  # takes a timestamp which will be used to schedule the job
  # for queueing.  Until timestamp is in the past, the job will
  # sit in the schedule list.
  def enqueue_at(timestamp, klass, *args)
    delayed_push(timestamp, :class => klass.to_s, :args => args, :queue => queue_from_class(klass))
  end

  # Identical to enqueue_at but takes number_of_seconds_from_now
  # instead of a timestamp.
  def enqueue_in(number_of_seconds_from_now, klass, *args)
    enqueue_at(Time.now + number_of_seconds_from_now, klass, *args)
  end

  # Used internally to stuff the item into the schedule sorted list.
  # +timestamp+ can be either in seconds or a datetime object
  # Insertion if O(log(n)).
  # Returns true if it's the first job to be scheduled at that time, else false
  def delayed_push(timestamp, item)
    # First add this item to the list for this timestamp
    redis.rpush("delayed:#{timestamp.to_i}", encode(item))

    # Now, add this timestamp to the zsets.  The score and the value are
    # the same since we'll be querying by timestamp, and we don't have
    # anything else to store.
    redis.zadd :delayed_queue_schedule, timestamp.to_i, timestamp.to_i
  end

  # Returns an array of timestamps based on start and count
  def delayed_queue_peek(start, count)
    redis.zrange(:delayed_queue_schedule, start, start+count).collect(&:to_i)
  end

  # Returns the size of the delayed queue schedule
  def delayed_queue_schedule_size
    redis.zcard :delayed_queue_schedule
  end

  # Returns the number of jobs for a given timestamp in the delayed queue schedule
  def delayed_timestamp_size(timestamp)
    redis.llen("delayed:#{timestamp.to_i}").to_i
  end

  # Returns an array of delayed items for the given timestamp
  def delayed_timestamp_peek(timestamp, start, count)
    if 1 == count
      r = list_range "delayed:#{timestamp.to_i}", start, count
      r.nil? ? [] : [r]
    else
      list_range "delayed:#{timestamp.to_i}", start, count
    end
  end

  # Returns the next delayed queue timestamp
  # (don't call directly)
  def next_delayed_timestamp
    timestamp = redis.zrangebyscore(:delayed_queue_schedule, '-inf', Time.now.to_i, 'limit', 0, 1).first
    timestamp.to_i unless timestamp.nil?
  end

  # Returns the next item to be processed for a given timestamp, nil if
  # done. (don't call directly)
  # +timestamp+ can either be in seconds or a datetime
  def next_item_for_timestamp(timestamp)
    key = "delayed:#{timestamp.to_i}"

    item = decode redis.lpop(key)

    # If the list is empty, remove it.
    if 0 == redis.llen(key).to_i
      redis.del key
      redis.zrem :delayed_queue_schedule, timestamp.to_i
    end
    item
  end

end

Resque.extend ResqueScheduler
Resque::Server.class_eval do
  include ResqueScheduler::Server
end