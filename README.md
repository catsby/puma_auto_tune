# Puma Auto Tune

## What

Performance without the (T)pain: `puma_auto_tune` will automatically adjust the number of [puma](https://github.com/puma/puma) workers to optimize the performance of your Ruby web application.

## Install

In your `Gemfile` add:

```ruby
gem 'puma_auto_tune'
```

Then run `$ bundle install`.

## Use

In your application call:

```ruby
PumaAutoTune.start
```

In Rails you could place this in an initializer such as `config/initializers/puma_auto_tune.rb`.

Puma Auto Tune will attempt to find an ideal number of workers for your application.


## Config

You will need to configure your Puma Auto Tune to be aware of the maximum amount of RAM it can use.

```ruby
PumaAutoTune.config do |config|
  config.ram = 512 # mb: available on system
end
```

The default is `512` which matches the amount of ram available on a Heroku dyno. There are a few other advanced config options:

```ruby
PumaAutoTune.config do |config|
  config.ram           = 1024 # mb: available on system
  config.frequency     = 20   # seconds: the duration to check memory usage
  config.reap_duration = 30   # seconds: how long `reap_cycle` will be run for
end
```

To see defaults check out [puma_auto_tune.rb](lib/puma_auto_tune/puma_auto_tune.rb)


## Hitting the Sweet Spot

Puma Auto Tune is designed to tune the number of workers for a given application while it is running. Once you restart the program the tuning must start over. Once the algorithm has found the "sweet spot" you can maximize your application throughput by manually setting the number of `workers` that puma starts with. To help you do this Puma Auto Tune outputs semi-regular logs with formatted values.

```
puma.total_memory_mb=476.6328125 puma.cluster_size=5
```

You can use a service such as [librato](https://metrics.librato.com/) to pull values out of your logs and graph them. When you see over time that your server settles on a given `cluster_size` you should set this as your default `puma -w <sweet-spot-number>` if you're using the CLI to start your app or if you're using a `config/puma.rb` file:

```ruby
workers #<sweet-spot-number>
```

Even better you can use the environment to store this value so you're not hard coding in values.


## Puma Worker Killer

Do not use with `puma_worker_killer` gem. Puma Auto Tune takes care of memory leaks in addition to tuning your puma workers.


## How it Works: Tuning Algorithm

Simple by default, custom for true Puma hackers. The best way to think of the tuner is to start with the different states of memory consumption Puma can be under:

- Unused ram: we can add a worker
- Memory leak (too much ram usage): we should restart a worker
- Too much ram usage: we can remove a worker
- Just right: No need to scale up or down.

The algorithm will periodically get the total memory used by Puma and take action appropriately.

#### Memory States: Unused Ram

The memory of the smallest worker is recorded. If adding another worker does not put the total memory over the threshold then one will be added.

#### Memory States: Memory Leak (too much ram usage)

When the amount of memory is more than that on the system, we assume a memory leak and restart the largest worker. This will trigger a check to determine if the result was due to a memory leak or because we have too many workers.

#### Memory States: Too much Ram Usage

After a worker has been restarted we will aggressively check for memory usage for a fixed period of time, default is 90 seconds(`PumaAutoTune.reap_reap_duration`). If memory goes over the limit, it is assumed that the cause is due to excess workers. The number of workers will be decreased by one. Puma Auto Tune will record the number of total workers that were present when we went over and set this as a new maximum worker number. After removing a process, Puma Auto Tune again checks for memory overages for the same duration and continues to decrement the number of workers until the total memory consumed is under the maximum.

#### Memory States: Just Right

Periodically the tuner will wake up and take note of memory usage. If it cannot scale up, and doesn't need to scale down it goes back to sleep.

## Customizing the Algorithm

Here's the fun part. You can write your own algorithm using the included hook system. The default algorithm is implemented as a series of [pre-defined hooks](lib/puma_auto_tune/default.rb).

You can over-write one or more of the hooks to add custom behavior. To define hooks call:

```ruby
PumaAutoTune.hooks do |auto|

end
```

Each hook has a name and can be over-written by calling the method name on the hook object.

- `cycle`
- `reap_cycle`
- `out_of_memory`
- `under_memory`
- `add_worker`
- `remove_worker`


Once you have the hook object you can use the `call` method to jump to other hooks.

### Cycle

This is the main event loop of your program. This code will be called every `PumaAutoTune.frequency` seconds. To over-write you can do this:


```ruby
PumaAutoTune.hooks do |auto|
  auto.cycle do |memory, master, workers|
    if memory > PumaAutoTune.ram # mb
      auto.call(:out_of_memory)
    else
      auto.call(:under_memory) if memory + workers.last.memory
    end
  end
end
```

### Reap Cycle

When you think you might run out of memory call the `reap_cycle`. The code in this hook will be called in a loop for `PumaAutoTune.reap_duration` seconds.

```ruby
PumaAutoTune.hooks do |auto|
  auto.reap_cycle do |memory, master, workers|
    if memory > PumaAutoTune.ram
      auto.call(:remove_worker)
    end
  end
end
```

## Add Worker

Bumps up the worker size by one.

```ruby
PumaAutoTune.hooks do |auto|
  auto.add_worker do |memory, master, workers|
    auto.log "Cluster too small. Resizing to add one more worker"
    master.add_worker
    auto.call(:reap_cycle)
  end
end
```

Here we're calling `:reap_cycle` just in case we accidentally went over our memory limit after the increase.

## Remove Worker

Removes a worker. When `remove_worker` is called it will automatically set `PumaAutoTune.max_workers` to be one less than the current number of workers.

```ruby
PumaAutoTune.hooks do |hook|
  auto.remove_worker do |memory, master, workers|
    auto.log "Cluster too large. Resizing to remove one worker"
    master.remove_worker
    auto.call(:reap_cycle)
  end
end
```

In case removing one worker wasn't enough we call `reap_cycle` again. Once a worker has been flagged with `restart` it will report zero RAM usage even if it has not completely terminated.

## License

MIT
