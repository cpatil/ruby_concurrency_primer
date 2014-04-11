require 'benchmark'
require './utils'
include Utils
include Utils::ProcessPool

ITERATIONS = 30
NUM_PROCESSES = 4

print_header

without_preforking = with_preforking = nil
Benchmark.bm(60) do |b|  

  without_preforking = [NUM_PROCESSES].collect do |num_processes|
    time_taken = nil
    b.report("no pre-forking workers, busy work (#{ITERATIONS} iters / #{num_processes} procs)") do
      time_taken = measure_time_taken do
        ITERATIONS.times.each_slice(num_processes) do |i|
          pids = num_processes.times.collect { fork { busy_work } }
          Process.waitall
        end
      end
    end
    [num_processes, time_taken]
  end

  with_preforking = [NUM_PROCESSES].collect do |num_processes|
    time_taken = nil
    b.report("with pre-forking workers, busy load (#{ITERATIONS} iters / #{num_processes} procs)") do
      pool = []
      time_taken = measure_time_taken do
        pool = create_worker_pool(num_processes)
        ITERATIONS.times.each { |i| send_task_to_free_worker(pool, :busy_work) }
      end
      begin
        worker = send_task_to_free_worker(pool, :exit); pool.delete(worker)
      end while pool.length > 0
    end
    Process.waitall
    [num_processes, time_taken]
  end
end
