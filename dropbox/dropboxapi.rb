# -*- coding: utf-8 -*-
require 'open-uri'
require 'net/http'
require 'net/https'
require 'cgi'
require 'openssl'
require 'yaml'
require 'digest/sha1'
require 'base64'
require 'erb'

$debug_flg = true

module Dropbox
  class AppInfo
    APP_KEY = "appkey"
    APP_SECRET = "appsecret"

    def initialize(filename)
      load filename
    end
    def load(filename)
      json = YAML.load_file filename
      @app_key    = json[APP_KEY]
      @app_secret = json[APP_SECRET]
      puts "key   :#{@app_key}"
      puts "secret:#{@app_secret}"
    end
    def get_app_key
      @app_key
    end
    def get_app_secret
      @app_secret
    end
  end

  class Oauth
    HMAC_SHA1 = "HMAC-SHA1"
    PLAINTEXT = "PLAINTEXT"

    def initialize(info)
      @app_key    = info.get_app_key    
      @app_secret = info.get_app_secret 
      @sig_method = PLAINTEXT
      @access_type = "app_folder"
    end
    def debug msg
      puts msg if $debug_flg
    end
    def signature_hmacsha1(params)
      debug("signature_hmacsha1")
      arr = params.collect{|k,v| "%s=%s"%[k,v]}
      sec = params[:oauth_token_secret] 
      sec = "" if sec == nil
      digest = OpenSSL::HMAC::digest(OpenSSL::Digest::SHA1.new,"%s&%s"%[@app_secret,sec],arr.sort.join("&"))
      #    Cgi.escape( Base64.b64encode( digest ))
      ERB::Util.u( Base64.b64encode( digest ).chomp)
    end

    def signature_plaintext(params)
      debug("signature_plaintext")
      sec = params[:oauth_token_secret]
      CGI.escape("%s&%s"%[@app_secret.chomp,sec])
    end

    def signature(params)
      debug("signature")
      case @sig_method
      when HMAC_SHA1
        @signature = signature_hmacsha1 params
      when PLAINTEXT
        @signature = signature_plaintext params
      else
	puts "else"
	return ""
      end
      return @signature
    end

    def nonce
      return @nonce unless @nonce == nil 
      @nonce = rand(100000000).to_s+Time.now.to_i.to_s
    end

    def get_oauth_token
      @params ={
        :oauth_consumer_key => @app_key,
        :oauth_timestamp    => Time.now.to_i.to_s,
        :oauth_nonce        => nonce,
        :oauth_signature_method => @sig_method,
        :oauth_version      => "1"
      } 
      return @params
    end

    def request_token # step 1
      debug("request_token")
      http = Net::HTTP.new("api.dropbox.com",443)
      http.use_ssl = true
      http.set_debug_output $stderr if $debug_flg
      path ="/1/oauth/request_token"
      
      params_tbl = get_oauth_token
      params = params_tbl.collect{|k,v| "%s=%s"%[k,v]}


      body = params.sort.join("&")

      params << "POST"
      params << "https://api.dropbox.com%s"%path
      body = "%s&oauth_signature=%s"%[body,signature(params_tbl)]

      resp, data = http.post(path, body)
      ret=Hash.new
      data.split("&").each do |e|
        kv = e.split("=")
        case kv[0]
        when "oauth_token_secret"
          ret.store :oauth_token_secret,kv[1]
        when "oauth_token"
          ret.store :oauth_token,kv[1]
        end
      end
      return ret
    end
    def authorize params
      debug("authorize")

      http = Net::HTTP.new("www.dropbox.com",443)
      http.use_ssl = true
      http.set_debug_output $stderr if $debug_flg
      path = "/1/oauth/authorize"
      params_tbl = Hash.new
      params_tbl.merge!( params )
      params_tbl.merge!( get_oauth_token )

      param_arr = params_tbl.collect{|k,v| "%s=%s"%[k,v]}
      
      body = param_arr.sort.join("&")

      param_arr << "GET"
      param_arr << "https://www.dropbox.com%s"%path

      body = body.concat("&oauth_signature=%s"%signature(params_tbl))
      puts "path:%s"%path
      puts "body:%s"%body
      system("open 'https://www.dropbox.com%s?%s'"%[path,body])
      sleep 10
      resp, data = http.post(path,body)
      
    end

    def access_token params
      debug("access_token")

      http = Net::HTTP.new("api.dropbox.com",443)
      http.use_ssl = true
      http.set_debug_output $stderr if $debug_flg
      path = "/1/oauth/access_token"
      params_tbl = Hash.new
      params_tbl.merge!( get_oauth_token )
      params_tbl.merge!( params )    

      param_arr = params_tbl.collect{|k,v| "%s=%s"%[k,v]}

      body = param_arr.sort.join("&")
      body = body.concat("&oauth_signature=%s"%signature(params_tbl))
      resp, data = http.post(path,body)
      puts "data:%s"%data
      ret = Hash.new
      data.split("&").each do |e|
        ele = e.split("=")
        case ele[0]
        when "oauth_token"
     	  ret.store(:oauth_token,ele[1])
        when "oauth_token_secret"
     	  ret.store(:oauth_token_secret,ele[1])
        when "uid"
     	  ret.store(:uid,ele[1])
        end
      end
      return ret
    end

    def authorization
      debug("authorization")
      req_token = request_token
      authorize req_token
      acc_token = access_token req_token 
      puts "oauth_token:%s"%acc_token[:oauth_token]
      puts "oauth_token_secret:%s"%acc_token[:oauth_token_secret]
      @params.store(:oauth_signature,signature(acc_token))
      @params.store(:oauth_token,acc_token[:oauth_token])
      
      return self
    end
    def get_token
      @params
    end
    def get_params
      @params.collect{|k,v| "%s=%s"%[k,v]}.join("&")
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

appinfo = Dropbox::AppInfo.new("dropbox.info")
#oauth = Dropbox::Oauth.new( Dropbox::AppInfo.new("dropbox.info") ).authorization
oauth = Dropbox::Oauth.new( appinfo ).authorization
params = oauth.get_token
puts "oauth_token:        #{params[:oauth_token]}"
puts "oauth_token_secret: #{params[:oauth_token_secret]}"
metadata = Dropbox::Metadata.new(oauth).open("sandbox","/<file name in your dropbox>").get_json
puts metadata["path"]
puts metadata["modified"]
