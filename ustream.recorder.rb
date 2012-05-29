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
class LiveRecorder < Common

def initialize url,save_dir
  @ustream_url = url
  @save_dir=save_dir
  get_amf url
end

def download video_url,streamname,title

  if video_url.nil?  || video_url.empty? \
    || streamname.nil? || streamname.empty? \
    || title.nil?      || title.empty? then
    return
  end
  begin
    video_url = remove_invalid_char video_url
    video_url =~ /rtmp:\/\/[^\/]*\/(.*)\/*$/ 
    app = $1
    now = Time.now
    filename = now.strftime("#{title} %Y年%m月%d日 %H時%M分 #{now.to_i.to_s}.flv")
    
    @io = Command.new("rtmpdump").do(["-vr %s"%video_url,
                                      "-f \"LNX 10,0,45,2\"",
                                      "-y %s"%streamname,
                                      "--app %s"%app,
                                      "--swfUrl http://www.ustream.tv/flash/viewer.swf",
                                      "-o \"%s/%s\""%[@save_dir,filename]
                                     ])
    
    @th = Process.detach @io.pid
  rescue => exc
    puts exc
    puts exc.backtrace
  end
end

def start_recording
  begin
    main_th = Thread.new do
      get_amf @ustream_url
      get_stream_url @amf_url
      download @video_url,@streamname,@title
    end
    
    main_th.join
    
  rescue => exc; puts exc; puts exc.backtrace; end
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

def isAlive?
    true
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
            LiveRecorder.new(url,@save_dir).main
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
end
Ustream::Scheduler.new("ustream.list.txt","video","api_key").main
#Ustream::Scheduler.new("http://dl.dropbox.com/u/489176/ustream.list.txt","video","api_key").main