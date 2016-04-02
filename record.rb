require 'em-proxy'
require 'yaml'
require 'fileutils'
require "http/parser"
require 'zlib'
require 'stringio'
require 'digest/sha1'
# require 'json'

require 'logger'


$db = {}
$db_data = {}

$enter = "enter"

# $g_cnt = 1
$g_ord = {}

$g_order_glob = 1

logger = Logger.new(STDOUT)
logger.level = Logger::WARN

def save_html_table

end  


def save_db

	File.open("recordings/#{ARGV[0]}_#{ARGV[1]}/db_#{ARGV[2]}.yaml", 'w'){|f| f.write YAML.dump($db) }
  
  root_uncomp = $root_path + "_uncomp"
  FileUtils.mkdir_p root_uncomp
  # go through each of the requests and save the file 
  $db.each do |k, v|
    if !File.exists? v[:filename]
      # write the file in the usual place
      File.open(v[:filename],"wb+"){|f| f.write $db_data[k]}        
      # if it ends with .gz, unzip it and write it to the _uncomp folder
      # if not just copy it to the unzipped folder 
      if v[:filename].match /\.gz$/
        unzipped_fn = File.join(root_uncomp,File.basename(v[:filename].gsub(/\.gz$/, "")))
        begin 
          unzipped_data = gunzip($db_data[k])
        rescue => exception 
          puts "=== #{File.basename(v[:filename])} === "
          puts exception.backtrace
          # raise
        end        
        File.open(unzipped_fn,"wb+"){|f| f.write unzipped_data}    
      else
        FileUtils.cp v[:filename], File.join(root_uncomp,File.basename(v[:filename]))
      end
    end  

  end

  save_html_table
end

def gunzip(data)
  io = StringIO.new(data, "rb")
  gz = Zlib::GzipReader.new(io)
  decompressed = gz.read
end

# system under test server listens on port 9293
# client sends requests on em-proxy (9292) which then forwards them to system ARGV[0] and port ARGV[1]
# if a request comes to port 9999 then it will be interpreted as a command to insert into
# the flow of the script, it will be inserted literally and not response will be sent back ??

abort("forwarding server not given") unless ARGV[0]
abort("forwarding port not given") unless ARGV[1]
abort("recording name not given") unless ARGV[2]

$root_path = "recordings/#{ARGV[0]}_#{ARGV[1]}/#{ARGV[2]}"
FileUtils.mkdir_p($root_path)


def manage_admin(ts, data)
  m = data.match(/admin_command\=(.*)/)
  if m 
    logger.info [:on_command, "#{m}"]
    # insert the command here in the flow of the script
    #data is the actual command which would be evaled later at replay Time
    $db[ts][:req] = m[1]
    $db[ts][:resp] = ["ADMIN"]     
    conn.send_data "INSERTED command #{m[1]}\r\n"
    data = nil
  end  
  return data
end

puts "==> forwarding to #{ARGV[0]}:#{ARGV[1]}"

Proxy.start(:host => "0.0.0.0", :port => 9292, :debug => false) do |conn|
  conn.server :srv, :host => ARGV[0], :port => ARGV[1].to_i

  conn.on_connect do |data,b|
   
    logger.info [:on_connect, data, b, conn.peer[1], conn.signature, $g_order_glob]
  end

  # modify / process request stream
  conn.on_data do |data|
    $g_order_glob += 1

    $g_ord[conn.peer[1]] = $g_ord[conn.peer[1]] ? $g_ord[conn.peer[1]] += 1 : $g_ord[conn.peer[1]] = 1
   
    parser = Http::Parser.new
    ret = {:method => nil, :url => nil, :headers => nil}
    parser.on_headers_complete = proc do
      ret[:method] = parser.http_method
      ret[:url] = parser.request_url      
      ret[:headers] = parser.headers        
    end
    parser.on_body = proc do |chunk|
      ret[:body] = ret[:body] ? ret[:body] << chunk : chunk
    end
    begin 
      parser << data    
    rescue Exception => e
      p e.message
      # ret[:body] = data      
    end
  
    # @request = "#{req[:url].split('?')[0]}".gsub!(/[^0-9A-Za-z.\-]/, '_')    
    @request = "#{ret[:url]}".gsub!(/[^0-9A-Za-z.\-]/, '_')    
    
    ts = "#{conn.peer[1]}_#{$g_ord[conn.peer[1]]}"
    if $db[ts]
      abort "ts #{ts} exists !!!"
    end

    filename = "#{$root_path}/%s_" % ts + "_#{@request}"
    
    $db[ts] =  { :order => $g_order_glob, :socket => conn.peer[1], :req => ret, :ts => Time.now.to_f , :resp_time => 0.0}   
    # $db_data[ts] = ""
    $db[ts][:filename] = filename

    $db[ts][:header_parsed] = false

    $db[ts][:resp] = []
   
    # manage the admin commands arriving through the same chanel 
    # data = manage_admin(ts,data)

    #uncomment to not accept gzipped content
    # data.gsub!("Accept-Encoding: gzip, deflate, sdch\r\n","")    
    data.gsub!(/Accept-Encoding:(.*)\r\n$/, "")
    # data.gsub!("Connection: keep-alive","Connection: Close")
    logger.info [:on_data, ts] 

    data
    
  end

  # modify / process response stream
  conn.on_response do |backend, resp|
  
    ts = "#{conn.peer[1]}_#{$g_ord[conn.peer[1]]}"

    logger.info [:on_response, resp.size, ts]

    headers_size = 0
    body_size = 0
    ret = {:status => nil, :headers => nil, :body => nil}
    parser = nil
    if !$db[ts][:header_parsed]

      parser = Http::Parser.new      
      parser.on_headers_complete = proc do
        ret[:status] = parser.status_code 
        ret[:headers] = parser.headers        
      end
      parser.on_body = proc do |chunk|
        ret[:body] = ret[:body] ? ret[:body] << chunk : chunk
      end
      parser << resp.clone    

      # File.open($db[ts][:filename],"ab+"){|f| f.write ret[:body] }
      $db_data[ts] = ret[:body]
      # File.open($db[ts][:filename],"ab+"){|f| f.write ret[:body] }
  
      if ret[:headers]["Content-Encoding"] == "gzip"
        $db[ts][:filename] =  $db[ts][:filename] + ".gz" 
      end  
        $db[ts][:header_parsed] = true
    else      
      if $db_data[ts]
        $db_data[ts] << resp 
      else
        $db_data[ts] = resp 
      end
    end  

    # update yaml for the response
    if ret[:headers]
      $db[ts][:resp]  = [{:status => ret[:status], :resp_headers => ret[:headers]}]
    end

    # update timestamps
    $db[ts][:resp]  << {:ts => Time.now.to_f, :size => resp.size}
    
    # update resp_time
    $db[ts][:resp_time] = $db[ts][:resp_time] + (Time.now.to_f - $db[ts][:ts] )

    

    resp
  end

  # termination logic
  conn.on_finish do |backend, name|
    logger.info [:on_finish, name]
    # terminate connection (in duplex mode, you can terminate when prod is done)
    unbind if backend == :srv
    save_db
  end
end