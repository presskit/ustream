
# if this script returns 504, execute this command.
# sudo postfix start
# 
# sending mail test
# echo "hello" | mail -s "test" kazu.yamazaki@gmail.com
#
# log
# tail -f /var/log/mail.log
#
require "rubygems"
require "tmail"
require "tlsmail"
require "net/smtp"
require "net/pop"
require "kconv"
#require 'cipher'
require 'yaml'

GMAIL_SETTING_FILE = 'config.yml'
module Mail
  class Gmail
    def initialize
#      yaml = Cipher.new.load(SETTING_FILE).decrypt
      yaml = YAML.load_file(File.expand_path(GMAIL_SETTING_FILE,File::dirname(__FILE__)))
      @userid   = yaml['gmail']['userid']
      @password = yaml['gmail']['password']
      @from     = yaml['gmail']['from']
      @to       = yaml['gmail']['to']
    end
    def send(subject,body)
      begin
        mail = TMail::Mail.new
        mail.to = @to #'kazu.yamazaki+kyamaz@gmail.com'
        mail.from = @from #'yama@kyamaz.org'
        mail.subject = subject.tojis
        mail.date = Time.now
        mail.mime_version = '1.0'
        mail.set_content_type 'text', 'plain', {'charset' => 'iso-2022-jp'}
        mail.body = body.tojis
        Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
        Net::SMTP.start('smtp.gmail.com', 587, 'kyamaz.org', @userid,@password,"plain") do |smtp|
          smtp.sendmail(mail.encoded, mail.from, mail.to)
        end
        return true
      rescue=>exc
        puts exc.backtrace
        return false
      end
    end
  end
  class Postfix
    def _send(subject,body)
      to = 'kazu.yamazaki@gmail.com'
      from = 'yama@kyamaz.org'
      
      data = "Subject: #{subject.tojis}\n" + body.tojis
      
      #  Net::SMTP.start(Socket.gethostname.to_s) do |smtp|
      Net::SMTP.start('localhost') do |smtp|
        smtp.sendmail data, from, to
      end
    end
    
    def send(subject,mail_body)
      begin
        to = 'kazu.yamazaki@gmail.com'
        from = 'yama@kyamaz.org'
        
        body =  "From: #{from} <#{from}>\n"
        body << "To: #{to}<#{to}>\n"
        body << "Subject: #{subject}\n"
        body << "Date: %s\n"%Time.now.strftime("%a, %d %b %Y %X")
        body << "Importance:high\n"
        body << "MIME-Version:1.0\n"
        body << "\n\n\n"
        # MESSAGE BODY
        body << mail_body
        
        Net::SMTP.start('localhost') do |smtp|
          smtp.sendmail body, from, to
        end
        return true
      rescue=>exc
        puts exc.backtrace
        return false
      end
    end
  end
end
## test
#Mail::Postfix.new.send("[TEST]send","test body")
#result = Mail::Gmail.new.send("テスト".toutf8,"テスト送信 #{Time.now.strftime("%m/%d %H:%M")}".toutf8)
#puts "result: #{result.to_s}"
