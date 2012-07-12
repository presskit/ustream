# -*- coding: utf-8 -*-
require 'open-uri'
require 'cgi'
require "rexml/document"
require "lib/command"
require "ustream"

$amf_url = "http://cdngw.ustream.tv/Viewer/getStream/1/%s.amf"
$api_uri = "http://api.ustream.tv/xml/channel/%s/getinfo?key=$API_KEY$"
PLAY_LIST="play.list"
$KCODE = "utf-8"
CurrentDir = Dir.pwd

module Ustream 
class Player < Common
	
def initialize(url,save_dir,api_key=nil)
  @ustream_url = url
  @opt = ""
  $api_key=api_key
end

def play(video_url,streamname,title)

  if video_url.nil?  || video_url.empty? \
  || streamname.nil? || streamname.empty? \
  || title.nil?      || title.empty? then
    return
  end

  begin 
    video_url = remove_invalid_char video_url
    video_url =~ /rtmp:\/\/[^\/]*\/(.*)\/*$/ 
    app = $1

    rtmpdump = Command.new("rtmpdump").full_cmd(["-vr %s"%video_url,
                                                 "-q",
                                      "-f \"LNX 10,0,45,2\"",
                                      "-y %s"%streamname,
                                      "--app %s"%app,
                                      "--swfUrl http://www.ustream.tv/flash/viewer.swf",
                                      "--live",
                                      "--timeout 600",
                                      "-o -"
                                     ])
    mplayer = Command.new("mplayer").full_cmd([
                                               "-cache 256",
                                               "-cache-seek-min 80",
                                               "-v",
                                               "-mc 10",
                                               "-dr",
                                               "-double",
                                               "-hardframedrop",
                                               "-really-quiet",
                                               "-" ])
#    system("%s | %s"%[rtmpdump,mplayer])
    io = open("| %s | %s"%[rtmpdump,mplayer])
#    return Process.detach io.pid
	return io
	
  rescue => exc
    puts exc
    puts exc.backtrace
  end
end

def start_playing
  begin
    th=""
    main_th = Thread.new do
      get_amf @ustream_url
      get_stream_url @amf_url

      puts "video_url : %s"%@video_url
      puts "streamname: %s"%@streamname
      puts "hashtag   : %s"%@hashtag
      puts "viewers   : %s"%@viewers

      th = play @video_url,@streamname,@title
      self.join
    end
    
    while !main_th.alive? 
    	sleep 0.2
    end 
    save_playist
    return th

  rescue => exc
    puts exc
    puts exc.backtrace
  end
end
def usage
  puts "usage:"
  puts "ruby ustream.mplayer.rb [URL]"
  puts "\n"
  load_playlist
  print_playlist
end

def print_playlist
  for i in 0...@play_list.size
    puts "%d: %s"%[i+1,@play_list[i]]
  end
end
def load_playlist
  @play_list = Array.new
  path = File.expand_path(PLAY_LIST,CurrentDir)
  open(path,"w").close unless File.exist? path
  open(path) do |list|
    while key = list.gets
      unless @play_list.include? key
        @play_list << key
      end
    end
  end
  
end

def save_playist
  if @channel==nil || @ust_name==nil || @play_list==nil
    raise "@channel=%s, @ust_name=%s, @play_list%s"%[@channel,@ust_name,@play_list]
  end
  url = "http://www.ustream.tv/%s/%s"%[@channel,@ust_name]
  unless @play_list.include? url
    open(File.expand_path(PLAY_LIST,CurrentDir),"a"){|f| f.write url+"\n"}
  end
  
end
def main
  if @ustream_url==nil
    usage
    exit 0
  end

  load_playlist
  if @ustream_url =~ /([0-9]*)/
    @ustream_url = @play_list[$1.to_i-1]
  end

  get_amf @ustream_url
  while true
    begin
      while !isOnline? ; sleep 1; end
      puts "[start playing] #{@title} "
      th = start_playing
      cnt=0
      while cnt<5
        if th!=nil #th.alive?
          cnt=0
        else
          cnt=cnt+1
        end
        get_stream_url get_amf(@ustream_url)
        puts "%s viewers: %s"%[Time.now.strftime("%H:%M:%S"),@viewers]
        sleep 30
      end
      puts "[end playing] #{@title}"
    rescue => exc; puts exc; puts exc.backtrace; end
  end
end

end
end
#Scheduler.new("ustream.list.txt","video","api_key").main
Ustream::Player.new(ARGV[0],"video").main
