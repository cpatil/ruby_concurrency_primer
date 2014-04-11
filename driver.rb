require 'benchmark'
require './utils'
include Utils
include Utils::Pg

ITERATIONS = 10
NUM_THREADS = 2
NO_THREADS = true
NO_PROCESS = true
NO_ASYNC_IO = false

print_header

with_process_arr = with_threading = without_threading = with_process = with_async = nil
Benchmark.bm(45) do |b|  

  b.report("sync_io work (#{ITERATIONS} iterations)") do
    without_threading = measure_time_taken do
      ITERATIONS.times.each do |i|
        sync_io_work
      end
    end
  end

  unless NO_ASYNC_IO
    b.report("async_io work (#{ITERATIONS} iterations)") do
      with_async = measure_time_taken do
        wait_for_results(ITERATIONS.times.collect do |i|
                           async_io_work
                         end)
      end
    end
  end
  
  unless NO_THREADS
    b.report("threaded async_io work (#{ITERATIONS} iters / #{NUM_THREADS} thrds)") do
      with_threading = measure_time_taken do
        ITERATIONS.times.each_slice(NUM_THREADS) do |i|
          NUM_THREADS.times.collect { Thread.new { async_io_work } }.each {|t| t.join}
        end
      end
    end
  end
  
  unless RUBY_PLATFORM == "java" || NO_PROCESS
    with_process_arr = [NUM_THREADS].collect do |num_threads|
      time_taken = nil
      b.report("process based async_io work (#{ITERATIONS} iters / #{num_threads} processes)") do
        time_taken = measure_time_taken do
          ITERATIONS.times.each_slice(num_threads) do |i|
            pids = num_threads.times.collect { fork { async_io_work } }
            Process.waitall
          end
        end
      end
      sleep 15  # let the processes calm down
      [num_threads, time_taken]
    end
  end

  unless NO_THREADS
    increase = with_threading > without_threading
    puts "-" * 80
    puts "Percentage #{ increase ? 'increase' : 'decrease'} in time taken with Thread concurrency: #{'%.2f' % (((without_threading - with_threading) / without_threading) * 100).abs}"
  end

  unless NO_PROCESS || RUBY_PLATFORM == "java"
    with_process_arr.each do |(num_threads, with_process)|
      increase = with_process > without_threading
      puts "-" * 80
      puts "Percentage #{ increase ? 'increase' : 'decrease'} in time taken with Process concurrency (#{num_threads} processes): #{'%.2f' % (((without_threading - with_process) / without_threading) * 100).abs}"
    end
  end
end
