# -*- coding: utf-8 -*-
require 'open-uri'
require 'cgi'
require "rexml/document"
require "lib/command"
require "ustream"

$amf_url = "http://cdngw.ustream.tv/Viewer/getStream/1/%s.amf"
$api_uri = "http://api.ustream.tv/xml/channel/%s/getinfo?key=$API_KEY$"
$KCODE = "utf-8"

module Ustream 
class Player < Common
	
def initialize(url,save_dir,api_key=nil)
  @ustream_url = url
  @opt = ""
  $api_key=api_key
  get_amf url
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
                                               "-framedrop",
                                               "-really-quiet",
                                               "-" ])
#    system("%s | %s"%[rtmpdump,mplayer])
    io = open("| %s | %s"%[rtmpdump,mplayer])
    return Process.detach io.pid

  rescue => exc
    puts exc
    puts exc.backtrace
  end
end

def start_playing
  begin
    main_th = Thread.new do
      get_amf @ustream_url
      get_stream_url @amf_url

      puts "video_url : %s"%@video_url
      puts "streamname: %s"%@streamname
      puts "hashtag   : %s"%@hashtag
      puts "viewers   : %s"%@viewers

      th = play @video_url,@streamname,@title
      serf.join
    end
    
    return main_th

  rescue => exc
    puts exc
    puts exc.backtrace
  end
end

def main
  
  while true
    begin
      while !isOnline? ; sleep 1; end
      puts "[start playing] #{@title} "
      th = start_playing
      cnt=0
      while cnt<5
        cnt=cnt+1 unless th.alive?
        get_stream_url get_amf(@ustream_url)
        puts "%s views: %s"%[Time.now.strftime("%H:%M"),@viewers]
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
