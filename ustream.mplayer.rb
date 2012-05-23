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
                                               "-" ])
    system("%s | %s"%[rtmpdump,mplayer])
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
      play @video_url,@streamname,@title
    end
    
    main_th.join
    
  rescue => exc
    puts exc
    puts exc.backtrace
  end
end

def wait_for_finishing_streaming
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
#    Process.kill('SIGHUP',@io.pid) if !@th.nil? && @th.alive?
  rescue => exc; puts exc.backtrace; end
end

def main
  
  begin
    while !isOnline? ; sleep 1; end
    puts "[start recording] #{@title} "
    start_playing
    #wait_for_finishing_streaming
    loop do
      sleep 10
    end
    puts "[end recording] #{@title}"
  rescue => exc; puts exc; puts exc.backtrace; end
end

end
end
#Scheduler.new("ustream.list.txt","video","api_key").main
Ustream::Player.new(ARGV[0],"video").main
