require 'em-proxy'
require 'yaml'


$db = {}

def save_db
	File.open('db.yaml', 'w'){|f| f.write YAML.dump($db) }
end

Signal.trap("INT") do |signo| 
	puts "saving session"
	save_db
	exit
end

# system under test server listens on port 9293
# client sends requests on em-proxy (9292) which then forwards them to 9293
# if a request comes to port 9999 then it will be interpreted as a command to insert into
# the flow of the script, it will be inserted literally and not response will be sent back ??


Proxy.start(:host => "0.0.0.0", :port => 9292, :debug => false) do |conn|
  conn.server :srv, :host => "localhost", :port => 9293  

  conn.on_connect do |data,b|
    puts [:on_connect, data, b].inspect
  end

  # modify / process request stream
  conn.on_data do |data|
  	@ts = Time.now.to_f.to_s
  	$db[@ts] =  { :socket => conn.peer[1], :req => data }  	
  	$db[@ts][:resp] = []
    p [:on_data, data]    
    m = data.match(/admin_command\=(.*)/)
    if m 
    	puts "command given = #{m}"
    	# insert the command here in the flow of the script
    	#data is the actual command which would be evaled later at replay Time
    	$db[@ts][:req] = m[1]
    	$db[@ts][:resp] = ["ADMIN"]    	

    	conn.send_data "INSERTED command #{m[1]}\r\n"
      data = nil
    else
    	data  
    end 	
  	

  end

  # modify / process response stream
  conn.on_response do |backend, resp|
    p [:on_response, backend, resp]
    $db[@ts][:resp]  << resp.clone
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