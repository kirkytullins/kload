require 'yaml'

class Analyzer
  attr_reader :ana
  def initialize(yaml_file)
    @ana = YAML.load_file('db.yaml')    
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

  def response_stats(req, opt = {})
    if @req_list.include?(req)
      trans = find_req(req)
      return {} unless trans
      # require 'pry'
      # binding.pry
      return trans[:resp].inject([]){|c,v| c << {:ts => v[:ts], :size => v[:size]}; c}
    end
  end

end

a = Analyzer.new('db.yaml')
a.request_list.each do |l|
  puts "transaction (#{l})"
  puts "\t #{a.response_stats(l)}"
end

require 'pry'
binding.pry