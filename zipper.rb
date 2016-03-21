require 'zlib'
require 'stringio'
require 'json'

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


compressed = File.open("recordings/loginb3/1458314628.764395__Saba_assets_collaboration_chat_xmppChatFrame.html_1", "rb").read

#data = (1..100).collect {|i| {"id_#{i}" => "value_#{i}" } }
require 'pry'
binding.pry

#contents = data.to_json

#compressed = gzip(contents)
decompressed = gunzip(compressed)

puts "compressed string:"
puts compressed

puts "decompressed success? #{decompressed == contents}"

puts "uncompressed data size: #{contents.length}"
puts "decompressed data size: #{compressed.length}"
puts "compress ratio: #{compressed.length.to_f / contents.length.to_f}"
