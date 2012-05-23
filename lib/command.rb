# -*- coding: utf-8 -*-

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
  def full_cmd params
  	return "%s %s"%[find(),params.join(" ")]
  end
  def exec params
    puts "|%s %s"%[find(),params]
    puts CGI.escape("|%s %s"%[find(),params])
    return open("| %s %s"%[find(),params])
  end

  def do params
    return exec params.join(" ")
  end
end
