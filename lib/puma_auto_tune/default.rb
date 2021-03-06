PumaAutoTune.hooks do |auto|
  # Runs in a continual loop controlled by PumaAutoTune.frequency
  auto.cycle do |memory, master, workers|
    if memory > PumaAutoTune.ram # mb
      auto.call(:out_of_memory)
    else
      auto.call(:under_memory) if memory + workers.last.memory
    end
  end

  # Called repeatedly for `PumaAutoTune.reap_duration`.
  # call when you think you may have too many workers
  auto.reap_cycle do |memory, master, workers|
    if memory > PumaAutoTune.ram
      auto.call(:remove_worker)
    end
  end

  # Called when puma is using too much memory
  auto.out_of_memory do |memory, master, workers|
    largest_worker = workers.last # ascending worker size
    auto.log "Potential memory leak. Reaping largest worker", largest_worker_memory_mb: largest_worker.memory
    largest_worker.restart
    auto.call(:reap_cycle)
  end

  # Called when puma is not using all available memory
  # PumaAutoTune.max_workers is tracked automatically by `remove_worker`
  auto.under_memory do |memory, master, workers|
    theoretical_max_mb = memory + workers.first.memory # assending worker size
    if theoretical_max_mb < PumaAutoTune.ram && workers.size + 1 < PumaAutoTune.max_workers
      auto.call(:add_worker)
    else
      auto.log "All is well"
    end
  end

  # Called to add an extra worker
  auto.add_worker do |memory, master, workers|
    auto.log "Cluster too small. Resizing to add one more worker"
    master.add_worker
    auto.call(:reap_cycle)
  end

  # Called to remove 1 worker from pool. Sets maximum size
  auto.remove_worker do |memory, master, workers|
    auto.log "Cluster too large. Resizing to remove one worker"
    master.remove_worker
    auto.call(:reap_cycle)
  end
end
