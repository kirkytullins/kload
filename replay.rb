require 'em-proxy'
require 'yaml'
require 'fileutils'
require "http/parser"
require 'zlib'
require 'stringio'
require 'digest/sha1'

require 'eventmachine'
require 'em-http'


# require 'json'
require 'awesome_print'
require 'pry'
  # binding.pry

$db = {}

def get_db
	$db = YAML.load_file("#{ARGV[0]}")
end

abort("script name for replay not given") unless ARGV[0]

get_db

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

# user the EM engine to send the requests 

puts "==> replaying script #{ARGV[0]}"

$hostname = ARGV[0].split('/')[1].split('_')[0]
$port = ARGV[0].split('/')[1].split('_')[1]

$db.each do |k, sl|
  url = sl[:req][:url]
  method = sl[:req][:method].downcase
  headers = sl[:req][:headers]
  pp "playing : #{method} #{url}"

  EventMachine.run {
    http = EventMachine::HttpRequest.new("http://" + $hostname + ":" + $port + url).send(method, {:head  => headers})

    http.errback { p 'Uh oh'; EM.stop }
    http.callback {
      p http.response_header.status
      p http.response_header
      p http.response

      EventMachine.stop
    }
  }

  # while sleep(1)
end

