class Profiler
  @t0 = nil

  def self.init(msg = 'START')
    @t0 = Time.now
    self.save(msg)
  end
  
  def self.save(msg)
    if @t0.nil?
      self.init
    end

    t = Time.now

    print "#{t.strftime('%H:%M:%S')} +#{(t - @t0).to_i} : #{msg}\n"
  end
end