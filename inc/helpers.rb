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

# Adapted from https://gist.github.com/j05h/673425
#   loc1 and loc2 are arrays of [latitude, longitude]
def compute_distance (lon1, lat1, lon2, lat2)
  def deg2rad(deg)
    return deg * Math::PI / 180
  end

  dLat = deg2rad(lat2-lat1)
  dLon = deg2rad(lon2-lon1)
  a = Math.sin(dLat/2) * Math.sin(dLat/2) +
      Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
      Math.sin(dLon/2) * Math.sin(dLon/2)
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
  d = (6371 * c * 1000).to_i
end