require 'oauth'

module Dropbox
  class Auth
  def initialize(filename)
    @filename = filename
  end
  def auth
    @oauth = Oauth::Authorization.new({:file,@filename})
    @oauth.authorize
    return self
  end
  def get_params
    @oauth.get_params
  end
end

  class AccountInfo
    def initialize oauth 
      @oauth = oauth
    end
    def open
      http = Net::HTTP.new("api.dropbox.com",443)
      http.use_ssl = true
      http.set_debug_output $stderr if $debug_flg
      path = "/1/account/info"
puts "path:%s,body:%s"%[path,@oauth.get_params]
      resp, data = http.post(path,@oauth.get_params)
      @json = YAML.load(data)
      return self
    end
    def get_json
      @json
    end
  end
  
  class Metadata
    def initialize oauth
      @oauth = oauth
    end
    def open(root,path)
      puts "[error] root must be dropbox or sandbox" if root!="dropbox" && root!="sandbox"
      http = Net::HTTP.new("api.dropbox.com",443)
      http.use_ssl = true
      http.set_debug_output $stderr if $debug_flg
      pth = "/1/metadata/%s/%s"%[root,path]
      resp, data = http.post(pth,@oauth.get_params.concat("&list=true"))
      @json = YAML.load(data)
      puts "[error] #{@json["error"]}" unless @json["error"]==nil
      return self
    end
    def get_json
      @json
    end
  end
end

oauth = Dropbox::Auth.new("dropbox.info").auth
puts Dropbox::AccountInfo.new(oauth).open.get_json
puts Dropbox::Metadata.new(oauth).open("sandbox","/ustream.list.txt").get_json
