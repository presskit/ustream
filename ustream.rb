require 'timeout'

module Ustream
class Common
def get_ustream_url
  return @ustream_url 
end

def remove_invalid_char str
  return "" if str.nil?
  return str.gsub(/[^0-9a-zA-Z~!@#$\%^&*\(\)_\-=+{}:\;'"<>\/,.\?]/,"")
end

def get_cid text
  text =~ /cid=([0-9]*)/ 
  return $1
end
 
def get_title(text)

  text =~ /<meta\s?property="og:title"\s*content="(.*?)"\s*\/>/
  return $1
end

def get_streamname(text)
  text =~ /streamName(.*)liveHttp/
  return remove_invalid_char $1
end

def get_amf(url)
begin
  url =~ /http:\/\/www.ustream.tv\/([^\/]*)\/?(.*)/
  puts "1:"+$1.to_s
  puts "2:"+$2.to_s
  uri = "http://www.ustream.tv/%s/%s"%[$1,CGI.escape($2)]
  timeout(10) do
    open(uri) do |file|
      line = file.read
      @cid = get_cid line
      @title = get_title line
      break unless @cid.nil? || @title.nil?
    end
  end
  @amf_url = $amf_url%@cid
  rescue Timeout::Error
    puts "timeout: %s"%url
  rescue => exc
    puts exc.backtrace
  end
end

def get_stream_url2(text)
  text =~ /[cdnUrl|fmsUrl].*(rtmp:\/\/)(.*)$/
  return remove_invalid_char '%s%s'%[$1,$2]
end

def get_stream_url(amf_url)
begin
  uri = URI.parse(amf_url)
  timeout(10) do
    uri.open do |file|
      line = file.read
      @video_url  = get_stream_url2 line
      @streamname = get_streamname  line
    end
  end
  rescue Timeout::Error
    puts "timeout: %s(%s)"%[@title,@cid]
  rescue => exc
    puts ext
    puts exc.backtrace
  end
end


def getinfo(cid)
    begin
      uri = URI.parse($api_uri%cid)
      @xml=nil
      doc=''
      timeout(10) do
       	 uri.open {|file| doc.concat(file.read) }
       	 @xml = REXML::Document.new(doc)
      end
    rescue Timeout::Error
        puts "timeout : %s(%s)"%[@title,@cid]
    rescue
	raise
    end
end

def getTitle
  return @title
end

def isOnline?
  getinfo @cid
  flg =  @xml.elements['xml/results/status'].text=='live'
  puts "#{flg.to_s} #{@title} (#{@cid})"
  return flg
end
end
end
