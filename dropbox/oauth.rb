require "open-uri"
require "net/https"
require "yaml"
require "cgi"

module Oauth
  HMAC_SHA1 = "HMAC-SHA1"
  PLAINTEXT = "PLAINTEXT"
  @debug_flg = true

  class Token
  	def initialize(token)
      	    @http   = token["http"]
      	    @method = token["method"]
      	    @host   = token["host"]
      	    @path   = token["path"]
	end
	def get_http
	    @http
	end
	def get_method
	    @method
	end
	def get_host
	    @host
	end
	def get_path
	    @path
	end
  end

  class Authorization
    def initialize params
    	if params[:file]!=nil
    	    load_file params[:file]
	end
    end

    def load_file(filename)
      json = YAML.load_file filename
      @consumer_key    = json["consumer_key"]
      @consumer_secret = json["consumer_secret"]
      @method = json["method"]
      @req_token   = Token.new(json["request_token"])
      @auth_token  = Token.new(json["authorize"])
      @access_token= Token.new(json["access_token"])
      return self
    end

    def create_params
      {
        :oauth_consumer_key => @consumer_key,
        :oauth_timestamp    => Time.now.to_i.to_s,
        :oauth_nonce        => nonce,
        :oauth_signature_method => @method,
        :oauth_version      => "1"
      } 
    end
    def get_params
      get_body @params
    end
    def authorize
        begin
          rq = @req_token
          ua = @auth_token
          at = @access_token
          params = create_params
          params = request_token rq.get_host,rq.get_path,params
          params = user_authorization ua.get_host,ua.get_path,params
          params = access_token at.get_host,at.get_path,params
          @params = params
	rescue => ext
	    puts ext
	    puts ext.backtrace
	end   
    end
    def request_token(host , path , params) #step 1
      raise "req token's params are not enough" unless check_request_token params
      params.store :oauth_signature , signature(params)
      resp , data =  post(host , path , get_body(params))
      data.split("&").each do |ele|
          e = ele.split("=")
        case e[0]
          when "oauth_token"
          params.store :oauth_token, e[1]
          when "oauth_token_secret"
          @oauth_token_secret = e[1]
        end
      end
      return params  
    end

    def user_authorization(host,path,params) #step 2
    puts params.collect{|k,v| puts "%s=%s,"%[k,v]}
#      params.store "GET",""
#      params.store "https://%s%s"%[host,path],""
      system("open 'https://%s%s?%s'"%[host , path, get_body(params)])
      sleep 10
      return params
    end

    def access_token(host,path,params) #step 3
      return unless check_access_token params
      resp, data =  post(host , path , get_body(params))
      data.split("&").each do |ele|
        e = ele.split("=")
        case e[0]
        when "oauth_token"
          params.store :oauth_token, e[1]
        when "oauth_token_secret"
          @oauth_token_secret = e[1]
        end
      end
      return params
    end

    def get_body params
      singarr = []
      pairarr = []
      params.collect do |k,v| 
        if v.to_s.empty? 
          singarr << k
        else 
          pairarr << "%s=%s"%[k,v] 
        end
      end

      singarr.concat(pairarr)
      body = singarr.join("&")
puts ""
      params.delete :oauth_signature unless params[:oauth_signature] ==nil
      body = "%s&oauth_signature=%s"%[body,signature(params)]
      return body
    end

    def signature(params)
      return if params[:oauth_signature_method]==nil
      case params[:oauth_signature_method]
      when HMAC_SHA1
        return Hmac_sha1.new(@consumer_secret,@oauth_token_secret,params).get_signature
      when PLAINTEXT
        return CGI.escape("%s&%s"%[@consumer_secret,@oauth_token_secret])
      else
        return
      end
    end

    def post(host,path,body)
      raise "host is nil" if host==nil
      raise "path is nil" if path==nil
      raise "body is nil" if body==nil

      http = Net::HTTP.new(host,443)
      http.use_ssl = true
      http.set_debug_output $stderr if @debug_flg
      
      return http.post(path, body)      
    end
    def check_tokens(params)
      raise "oauth_consumer_key is nil" if params[:oauth_consumer_key] == nil
      raise "oauth_signature_method is nil"  if params[:oauth_signature_method] == nil
      raise "oauth_timestamp is nil" if params[:oauth_timestamp] == nil
      raise "oauth_nonce is nil" if params[:oauth_nonce] == nil
      raise "oauth_version is nil" if params[:oauth_version] == nil
      return true
    end
    def nonce
      return @nonce unless @nonce == nil 
      @nonce = rand(100000000).to_s+Time.now.to_i.to_s        
    end
    def check_request_token(params)
      return check_tokens params
    end
    def check_access_token(params)
      return check_tokens params
    end
  end

  class Hmac_sha1
    def initialize(consumer_secret,oauth_token_secret,params)
        @consumer_secret = consumer_secret
        @oauth_token_secret = oauth_token_secret
        @params = params
    end

    def get_signature
        body = @params.collect{|k,v| "%s=%s"%[k,v]}.sort.join("&")
        digest = OpenSSL::HMAC::digest(OpenSSL::Digest::SHA1.new,"%s&%s"%[@consumer_secret,@oauth_token_secret])
    end
 end  
end
