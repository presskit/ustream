# -*- coding: utf-8 -*-
require 'open-uri'
require 'cgi'
require "rexml/document"


$amf_url = "http://cdngw.ustream.tv/Viewer/getStream/1/%s.amf"
$api_uri = "http://api.ustream.tv/xml/channel/%s/getinfo?key=$API_KEY$"
$KCODE = "utf-8"

class Command
  def initialize cmd
    @cmd = cmd
    @full_cmd=""
  end
  
  def which
    return @full_cmd unless @full_cmd.empty?
    @full_cmd=""
    IO.popen("which #{@cmd}") {|pipe|
      pipe.each{|line| 
        return @full_cmd=line.gsub("\n","") unless line.empty?
      }
    }
    return @full_cmd
  end
  
  def find
    return which unless which.empty?

    ["/bin","/sbin","/usr/bin","/usr/local/bin","/usr/sbin","/usr/local/sbin"].each do |p|
      com_path = "%s/%s"%[p,@cmd]
      return com_path if File.exists?(com_path) 
    end

  end
  
  def exec params
    puts "|%s %s"%[find(),params]
    return open("|%s %s"%[find(),params])
  end

  def do params
    return exec params.join(" ")
  end
end

class UstreamLive
	
def initialize url,save_dir
  @ustream_url = url
  @save_dir=save_dir
  get_amf url
end

def get_ustream_url
  return @ustream_url 
end

def remove_invalid_char str
  return "" if str.nil?
#  str.gsub!(/[^0-9a-zA-Z-_\/]/,"")
  str = CGI.escape(str)
  #str = str.gsub(/%02|%0C|%00|%17|%0B|%15|%10/){""}
  str.gsub!(/%02|%0C|%00|%17|%0B|%15|%10|%18|%11/,"")
  return CGI.unescape(str)
end

def get_cid text
  text =~ /cid=([0-9]*)/ 
  return $1
end
 
def get_title text

  text =~ /<meta\s?property="og:title"\s*content="(.*?)"\s*\/>/
  return $1
end

def get_streamname text
  text =~ /streamName(.*)liveHttp/
  return remove_invalid_char $1
end

def get_amf url
  url =~ /http:\/\/www.ustream.tv\/([^\/]*)\/(.*)/
  puts "1:"+$1.to_s
  puts "2:"+$2.to_s
  uri = "http://www.ustream.tv/%s/%s"%[$1,CGI.escape($2)]
  open(uri) do |file|
    line = file.read
    @cid = get_cid line
    @title = get_title line
    break unless @cid.nil? || @title.nil?
  end
  @amf_url = $amf_url%@cid
end

def get_stream_url2 text
  text =~ /[cdnUrl|fmsUrl].*(rtmp:\/\/)(.*)$/
  return remove_invalid_char '%s%s'%[$1,$2]
end

def get_stream_url amf_url
  uri = URI.parse(amf_url)
  open(uri) do |file|
    line = file.read
    @video_url  = get_stream_url2 line
    @streamname = get_streamname  line
  end

end

def download_stream video_url,streamname,title

  return if video_url.nil?  || video_url.empty? 
  return if streamname.nil? || streamname.empty?
  return if title.nil?      || title.empty?
  
  video_url = remove_invalid_char video_url
  video_url =~ /rtmp:\/\/[^\/]*\/(.*)\/*$/ 
  app = $1
  date = Time.now
  filename = date.strftime("#{title} %Y年%m月%d日 %H時%M分 #{date.to_i.to_s}.flv")
  
  @io = Command.new("rtmpdump").do(["-vr %s"%video_url,
                                    "-f \"LNX 10,0,45,2\"",
                                    "-y %s"%streamname,
                                    "--app %s"%app,
                                    "--swfUrl http://www.ustream.tv/flash/viewer.swf",
                                    "-o \"%s/%s\""%[@save_dir,filename]
                                   ])
  
  @th = Process.detach @io.pid

end

def getinfo cid
  uri = URI.parse($api_uri%cid)
  doc=''
  open(uri) {|file| doc.concat(file.read) }
  @xml = REXML::Document.new(doc)
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

def start_recording
  begin
    main_th = Thread.new do
      get_amf @ustream_url
      get_stream_url @amf_url
      download_stream @video_url,@streamname,@title
    end
    
    main_th.join
    
  rescue => exc; puts ext; puts exc.backtrace; end
end

def wait_for_finishing_recording
  begin
    timeout=20
    offair_sec=timeout.to_i
    while offair_sec>0 && !@th.nil? && @th.alive?
      offair_sec=timeout.to_i
      while !isOnline? && offair_sec>0 && !@th.nil? && @th.alive?
        offair_sec-=1
        sleep 1
      end
      #		puts "offair_sec:#{_offair_sec}"
      sleep 1
    end
    Process.kill('SIGHUP',@io.pid) if !@th.nil? && @th.alive?
  rescue => exc; puts exc.backtrace; end
end

def main
  
  begin
    while !isOnline? ; sleep 1; end
    puts "[start recording] #{@title} "
    start_recording
    wait_for_finishing_recording
    puts "[end recording] #{@title}"
  rescue => exc; puts exc.backtrace; end
end

end

class Scheduler
  def initialize file,save_dir, api_key_file
    @list_file = file
    read_api_key api_key_file
    @save_dir = save_dir
    Dir::mkdir(save_dir) unless File.exists?(save_dir)
  end
  
def read_api_key api_key_file
    f = open(api_key_file)
    api_key = f.gets
    f.close
    $api_uri=$api_uri.gsub("$API_KEY$",api_key)
end
	
def updated?
  mtime = File::stat(@list_file).mtime
  if @mtime==0||mtime>@mtime
    @mtime = mtime
    puts "the list file was updated at #{@mtime}"
    return true
  else
    return false
  end
end

def read_url_list
  @ustream_lives = []
  f=open(@list_file,"r")
  f.each do |line|
    puts line
    @ustream_lives << line if line =~ /^http:\/\/.*/
    @online_url[line] = false
  end
  f.close
end

def main
  @mtime = 0
  @ustream_lives=[]
  @online_url = Hash::new
  thread_que = []
  th=Thread.new do
    loop do
      read_url_list if updated?
      @ustream_lives.each do |url|
        if !@online_url[url]
          thread_que << Thread.new do
            @online_url[url]=true
            UstreamLive.new(url,@save_dir).main
            @online_url[url]=false
          end
        end
      end
      sleep 1
    end
  end
  
  th.join
  
  loop do
    while thread_que.size>0
      thread_que.pop.join
    end
    sleep 1
  end

end
end

Scheduler.new("ustream.list.txt","video","api_key").main
