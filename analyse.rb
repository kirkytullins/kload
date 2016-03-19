require 'yaml'

class Analyzer
  attr_reader :ana
  def initialize(yaml_file)
    @ana = YAML.load_file(yaml_file)    
    @req_list = request_list
  end

  def request_list    
    @req_list = @ana.inject([]){|c, (k,v)| c << v[:req][:url]; c }
  end
  
  def request_list_short    
    @req_list.inject([]){|c, ff| c <<  ff.split('?')[0]; c}
  end

  def find_req(req)
    @ana.select do |k,v|
      return v if v[:req][:url] == req
    end
    return {}
  end

  def calc_totals(l)
    ret = {:delta => 0.0, :tot_size => 0}
    l.each do |r|
      ret[:delta]
    end
  end
  
  def shorten(in_url)
    in_url.split('?')[0]
  end

  def response_times
    resp = @ana.inject([]) do |h, (r, k)|
      c = {}
      # c[:url] = shorten(k[:req][:url])
      c[:url] = k[:req][:url]
      c[:resp_time] = k[:resp_time]
      c[:resp_size] = k[:resp].inject(0){|c,l| c = c + l[:size]; c}
      h << c
      h
    end    
    resp << { :url => 'TOTAL TIMES AND SIZES', 
                :resp_time => resp.inject(0){|s,l| s = s+ l[:resp_time]},
                :resp_size => resp.inject(0){|s,l| s = s+ l[:resp_size]}
            }

  end
  def response_stats(req, opt = {})
    if @req_list.include?(req)
      trans = find_req(req)
      return {} unless trans
      return trans[:resp].inject([]){|c,v| c << {:ts => v[:ts], :size => v[:size]}; c}
      # return get_totals(trans[:resp].inject([]){|c,v| c << {:ts => v[:ts], :size => v[:size]}; c}) if opt[:type] == :totals
        
    end
  end

end

abort("recording name not given") unless ARGV[0]

a = Analyzer.new("db_#{ARGV[0]}.yaml")
# puts "response time and sizes for #{ARGV[0]}"
r = a.response_times
puts r[0].keys.join(",")
r.each{|l| puts l.values.join(",")}

# require 'pry'
# binding.pry

