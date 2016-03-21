require 'em-proxy'
require 'yaml'
require 'fileutils'
require "http/parser"
require 'zlib'
require 'stringio'
# require 'json'


$db = {}

$g_cnt = 1

def save_db
	File.open("db_#{ARGV[2]}.yaml", 'w'){|f| f.write YAML.dump($db) }
end


def gunzip(data)
    io = StringIO.new(data, "rb")
    gz = Zlib::GzipReader.new(io)
    decompressed = gz.read
  end
  
def gzip(string)
    wio = StringIO.new("w")
    w_gz = Zlib::GzipWriter.new(wio)
    w_gz.write(string)
    w_gz.close
    compressed = wio.string
end


# system under test server listens on port 9293
# client sends requests on em-proxy (9292) which then forwards them to system ARGV[0] and port ARGV[1]
# if a request comes to port 9999 then it will be interpreted as a command to insert into
# the flow of the script, it will be inserted literally and not response will be sent back ??

abort("forwarding server not given") unless ARGV[0]
abort("forwarding port not given") unless ARGV[1]
abort("recording name not given") unless ARGV[2]

$root_path = "recordings/#{ARGV[2]}"
FileUtils.mkdir_p($root_path)

def parse_server_response(data)
  begin 
    parser = Http::Parser.new
    ret = {:status => nil, :headers => nil, :body => nil}

    parser.on_headers_complete = proc do
      ret[:status] = parser.status_code # for responses
      ret[:headers] = parser.headers        
    end

    parser.on_body = proc do |chunk|

      # One chunk of the body
      # p chunk
      if ret[:body]
        ret[:body] = ret[:body] + chunk 
        p "append in body, size : #{chunk.size}"
      else
        ret[:body] = chunk
        p "in body, size : #{chunk.size}"
      end

    end

    parser.on_message_complete = proc do |env|
      # Headers and body is all parsed
      # puts "Done!"
      # return ret
    end

    parser << data
    return ret
   rescue Exception => e
     p e.message
     ret[:body] = data
     # require 'pry'
     # binding.pry
     return ret
   end
end

def parse_client_request(data)
  begin 
    parser = Http::Parser.new
    ret = {}
    parser.on_headers_complete = proc do
      ret[:method] = parser.http_method
      ret[:url] = parser.request_url      
      ret[:headers] = parser.headers        
    end

    parser.on_body = proc do |chunk|
      # One chunk of the body
      # p chunk
      ret[:body] = chunk
    end

    parser.on_message_complete = proc do |env|
      # Headers and body is all parsed
      # puts "Done!"
      # return ret
    end

    parser << data
    return ret
   rescue Exception => e
     p e.message
     ret[:body] = data
     return ret
   end
end


puts "==> forwarding to #{ARGV[0]}:#{ARGV[1]}"

Proxy.start(:host => "0.0.0.0", :port => 9292, :debug => false) do |conn|
  conn.server :srv, :host => ARGV[0], :port => ARGV[1].to_i

  conn.on_connect do |data,b|
    puts [:on_connect, data, b].inspect
  end

  # modify / process request stream
  conn.on_data do |data|
    @filename = nil
    @gzip = ""

  	@ts = Time.now.to_f.to_s
  	$db[@ts] =  { :socket => conn.peer[1], :req => parse_client_request(data), :ts => Time.now.to_f , :resp_time => 0.0}  	
  	$db[@ts][:resp] = []
    @request = "#{$db[@ts][:req][:url]}".gsub!(/[^0-9A-Za-z.\-]/, '_')
    @filename = "#{$root_path}/#{conn.peer[1]}_#{@ts}_#{@request}"
    # p [:on_data, data]    
    # m = data.match(/admin_command\=(.*)/)
    # if m 
    # 	puts "command given = #{m}"
    # 	# insert the command here in the flow of the script
    # 	#data is the actual command which would be evaled later at replay Time
    # 	$db[@ts][:req] = m[1]
    # 	$db[@ts][:resp] = ["ADMIN"]    	

    # 	conn.send_data "INSERTED command #{m[1]}\r\n"
    #   data = nil
    # else
    	data  
    # end 	
  	
  end

  # modify / process response stream
  conn.on_response do |backend, resp|
    p [:on_response, backend, resp.size, conn.peer[1]]

    d = parse_server_response(resp)
    #write the response in the file and set the file name in the body
    if !@filename && d[:headers] 
      # require 'pry'
      # binding.pry      
      gzip = ".zip" #if d[:headers]["Content-Encoding"].match(/gzip/) rescue false
    end
    # request = "#{$db[@ts][:req][:url].split('?')[0]}#{gzip}".gsub("\/","_")
    
    
    # File.open(filename,"ab+"){|f| f.write d[:body] }
    File.open(@filename,"ab+"){|f| f.write resp }

    d[:body] = @filename +  $g_cnt.to_s
    $g_cnt += 1

    $db[@ts][:resp]  << {:ts => Time.now.to_f, :size => resp.size}.merge(d)
    $db[@ts][:resp_time] = $db[@ts][:resp_time] + (Time.now.to_f - $db[@ts][:ts] )
    resp
  end

  # termination logic
  conn.on_finish do |backend, name|
    p [:on_finish, name]
    # terminate connection (in duplex mode, you can terminate when prod is done)
    unbind if backend == :srv
    save_db
  end
end