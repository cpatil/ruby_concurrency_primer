require 'rbconfig'

module Utils
  def print_header
    puts "-" * 80
    puts " RUBY_PLATFORM: #{RUBY_PLATFORM}  RUBY_VERSION: #{RUBY_VERSION} RUBY_INSTALL_NAME: #{RbConfig::CONFIG['RUBY_INSTALL_NAME']}"
    puts "-" * 80
  end

  def mixed_work
    start = Time.now
    while (foo = Time.now - start) < 5.0
      i=0; loop { break if 400000 < (i=i+1); dirs = Dir.glob(ENV['HOME']) }
    end
  end

  def busy_work
    a=i=0; loop { break if 10000000 < (i=i+1); a += (i << 32) }
  end

  def measure_time_taken
    t = Time.now
    yield
    return Time.now - t
  end

  module Pg
    unless RUBY_PLATFORM == "java"
      require 'rubygems' # for MRI 1.8.*
      require 'pg'
      def sync_io_work
        ::PGconn.new({:dbname => 'rsv2_mls', :user => 'realscout', :password => '123foo', :host => '127.0.0.1'}).exec("SELECT pg_sleep(3)")
      end
      alias :blocking_db_call :sync_io_work

      def async_io_work
        conn = ::PGconn.new({:dbname => 'rsv2_mls', :user => 'realscout', :password => '123foo', :host => '127.0.0.1'})
        conn.setnonblocking(true)
        conn.send_query("SELECT pg_sleep(3)")
        conn
      end

      def wait_for_results(conns)
        hsh = conns.inject({}) {|a,c| a[IO.new(c.socket)] = { :conn => c, :done => false}; a}
        loop do
          break if hsh.values.collect {|v| v[:done]}.all?
          res = select(hsh.keys.select {|k| !hsh[k][:done]}, nil, nil, 0.1)
          res.first.each {|s| hsh[s][:done] = process_non_blocking_event(hsh[s][:conn])} if res
        end
      end

      def process_non_blocking_event(conn)
        conn.consume_input
        unless conn.is_busy
          res, data = 0, []
          while res != nil
            res = conn.get_result
            res.each {|d| data.push d} unless res.nil?  
          end
          return true
        end
        return false
      end

    end
  end

  module ProcessPool
    def create_worker_pool(num_workers)
      num_workers.times.collect do |i| 
        m_r,m_w, w_r,w_w= IO.pipe + IO.pipe
        if fork
          m_r.close; w_w.close
          { :r => w_r, :w => m_w }
        else
          # worker code
          m_w.close; w_r.close; r = m_r; w = w_w
          loop { w.write "ready"; cmd_len = r.read(2); cmd=r.read(cmd_len.to_i); send(cmd.to_sym) }
        end
      end
    end

    def send_task_to_free_worker(pool, task)
      free_worker = wait_for_free_worker(pool)
      free_worker[:w].write(((cmd_len = task.to_s.length) > 9) ? cmd_len.to_s : "0#{cmd_len}")
      free_worker[:w].write task.to_s
      free_worker
    end

    def wait_for_free_worker(pool)
      read_handles = pool.collect {|v| v[:r]}
      ready_read_handle = IO.select(read_handles).first.first; ready_read_handle.read(5)
      pool.detect {|v| v[:r] == ready_read_handle}
    end
  end

end
