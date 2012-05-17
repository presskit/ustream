# -*- coding: utf-8 -*-
require 'open-uri'
require 'cgi'
require "rexml/document"

$amf_url = "http://cdngw.ustream.tv/Viewer/getStream/1/%s.amf"
$api_uri = "http://api.ustream.tv/xml/channel/%s/getinfo?key=$API_KEY$"

class Command
  # dur秒後に強制終了
  def initialize cmd
    @cmd = cmd
    @full_cmd=""
  end
  
  def which
    return @full_cmd unless @full_cmd.empty?
    @full_cmd=""
    IO.popen("which #{@cmd}") {|pipe|
      pipe.each{|line| @full_cmd=line.gsub("\n","")}
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

def remove_escape_seq str
  return "" if str==nil
  
  str = CGI.escape(str)
  ["%02","%0C","%00","%17","%0B","%15","%10"].each{|ch| str = str.gsub(ch,"") }
  return CGI.unescape(str)
end

def get_cid text
  text =~ /cid=([0-9]*)/ 
  return $1
end

def get_title text
  text =~ /<meta\s?property="og:title"\s?content="(.*?)"\s?\/>/
  return $1
end

def get_streamname text
  text =~ /streamName(.*)liveHttp/
  return remove_escape_seq $1
end

def get_amf url
  url =~ /http:\/\/www.ustream.tv\/channel\/(.*)/
  uri = URI.parse "http://www.ustream.tv/channel/%s"%CGI::escape($1)
  open(uri) do |file|
    line = file.read
    @cid = get_cid line
    @title = get_title line
    break if @cid !=nil && @title!=nil
  end
  @amf_url = $amf_url%@cid
end

def get_stream_url2 text
  text =~ /[cdnUrl|fmsUrl].*(rtmp:\/\/)(.*)$/
  return '%s%s'%[$1,$2]
end

def get_stream_url amf_url
  uri = URI.parse(amf_url)
  open(uri) do |file|
    line = file.read
    @video_url = get_stream_url2 line
    @streamname = get_streamname line
  end
  @video_url = remove_escape_seq @video_url
end

def download_stream video_url,streamname,title
  return if video_url==nil || video_url.empty? || streamname==nil || streamname.empty? || title==nil || title.empty?
  
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
  return @xml.elements['xml/results/status'].text=='live'
end

def start_recording
  begin
    main_th = Thread.new do
      get_amf @ustream_url
      get_stream_url @amf_url
      download_stream @video_url,@streamname,@title
    end
    
    main_th.join
    
  rescue => exc; puts exc; end
end

def wait_for_finishing_recording
  begin
    _timeout=20
    _offair_sec=_timeout
    while _offair_sec>0&&@th!=nil&&@th.alive?
      _offair_sec=_timeout
      while !isOnline? && _offair_sec>0&&@th!=nil&&@th.alive?
        _offair_sec-=1
        sleep 1
      end
      #		puts "offair_sec:#{_offair_sec}"
      sleep 1
    end
    Process.kill('SIGHUP',@io.pid) if @th!=nil&&@th.alive?
  rescue => exc; puts exc; end
end

def main
  
  begin
    while !isOnline? ; sleep 1; end
    puts "[start recording] #{@title} "
    start_recording
    wait_for_finishing_recording
    puts "[end recording] #{@title}"
  rescue => exc; puts exc; end
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
