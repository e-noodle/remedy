class Url
      
    attr_accessor :max_attempts, :attempts, :user_agent, :headers_defaults 

    # Create an instance of this class
    def initialize
        @attempts       = 0
        @max_attempts   = 30        
        @headers_defaults = {   
            'Accept-Encoding'   => 'gzip, deflate',
            'Accept-Language'   => 'en-US,en;q=0.8',
            'User-Agent'        => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.71 Safari/537.36',
            'Connection'        => 'keep-alive'
        }
        @user_agent             = @headers_defaults['User-Agent']  
    end
 
    def process_http_response response

        page = nil
        
        case response
        when Net::HTTPSuccess then  
            begin 

              if response.header[ 'Content-Encoding' ].eql?( 'gzip' ) then    
                sio = StringIO.new( response.body )
                gz = Zlib::GzipReader.new( sio )
                page = gz.read()
              else          
                page = response.body
                
              end       
      
            rescue Exception
              debug.call( "Error occurred (#{$!.message})" )
              raise $!.message
            end 
        end
        
        return page

    end
 
    def getUrl_with_cookies(get_url, cookie_monster, get_request_headers = nil, get_body = nil) 

    
        logs = ""

        get_url                 = get_url
        get_uri                 = URI(get_url)
        get_https               = Net::HTTP.new(get_uri.host,get_uri.port)
        
        if get_uri.instance_of? URI::HTTPS
            get_https.use_ssl       = true
            get_https.verify_mode   = OpenSSL::SSL::VERIFY_NONE
        end
        
        get_https.set_debug_output(logs); 
        
        if not get_body.nil?
            get_uri.query         = URI.encode_www_form(get_body)
        end		
        
        get_request               = Net::HTTP::Get.new(get_uri.request_uri)
  
        get_header = {}
        get_header['Cookie']     = cookie_monster.get_cookie_header(get_uri)
        
        get_header.each {  |header,value| get_request["#{header}"] = "#{value}" }
        get_request_headers.each{ |k,v| get_request[k] = "#{v}" }

        get_response  = get_https.request(get_request)
        #get_request.each_header{|h|puts "#{h}: #{get_request[h]}"}
        logger(logs)

        cookie_monster.get_response_cookies(get_response, get_uri, cookie_monster.jar)
        cookie_monster.save_cookies 
        
        return get_response
    end
 
  
    def postUrl_with_cookies(post_url, cookie_monster, post_request_headers = nil, post_body = nil ) 

        post_url               = post_url
        post_uri               = URI(post_url)
        post_https             = Net::HTTP.new(post_uri.host,post_uri.port)
        
        if post_uri.instance_of? URI::HTTPS
            post_https.use_ssl      = true
            post_https.verify_mode  = OpenSSL::SSL::VERIFY_NONE
        end
  
        post_request           = Net::HTTP::Post.new(post_uri.path)
        unless post_request_headers.nil?
            post_request_headers.each{ |k,v| post_request[k] = v }   
        end   
        
        # add cookies / todo: post from session
        
        post_request['Cookie'] = cookie_monster.get_cookie_header(post_uri)
        
        if not post_body.nil?
            post_request.body="#{post_body['param']}&sToken=#{post_body['sToken']}"
            post_request['Content-Length'] = post_request.body.to_s.length
        end
    
        logs = ""
        post_https.set_debug_output(logs)
        
        post_response = post_https.request(post_request)
        
        logger(logs)

        cookie_monster.get_response_cookies(post_response, post_uri, cookie_monster.jar)
        cookie_monster.save_cookies
        
        return post_response
    end
  
  
    def get(get_url, get_request_headers, cookie_monster, request_body = false)
 
        return nil if get_url.nil?    
        
        found     = false
        attempts  = 0 
        get_response  = nil       
        get_uri       = URI(get_url)
        

        until( found || attempts >= @max_attempts)
             
            attempts            	+= 1
            get_http                = Net::HTTP.new(get_uri.host,get_uri.port)
            get_http.open_timeout   = 10
            get_http.read_timeout   = 10
            if get_uri.instance_of? URI::HTTPS
                get_http.use_ssl      = true
                get_http.verify_mode  = OpenSSL::SSL::VERIFY_NONE
            end 
           
            get_path                = get_uri.path
            get_path                = "/" if get_path == ""
            get_path                = "#{get_path}?#{get_uri.query}" unless get_uri.query.nil?
            
            get_request = Net::HTTP::Get.new(get_path,{'User-Agent' => @user_agent}) 
            
            get_request_headers['Cookie'] = cookie_monster.get_cookie_header(get_uri)           

            get_request.initialize_http_header(get_request_headers)
            get_response 			  = get_http.request(get_request)
            
            #resp = self.getUrl_with_cookies("https://"+uri.host+path, cookie_monster, headers) 
             
            case get_response
            when Net::HTTPSuccess
                if get_response.code == "200"
                    page = process_http_response(get_response)        
                    IO.write("?#{get_uri.query}", page) unless page.nil?    
                    get_response.header['Referer'] = get_uri.to_s
                    found = true					
                    #return resp                
                end
            when Net::HTTPRedirection
                
                if (get_response.header['location'] != nil)          
                    newurl = URI.parse(get_response.header['location'])               
                    
                    if(newurl.relative?)
                        newurl = url+get_response.header['location']
                    end   

                    if File.exists?("?#{get_uri.query}")
                      file = File.stat "?#{get_uri.query}"
                      get_request_headers['If-Modified-Since']  = file.mtime.rfc2822
                    end
                    
                    get_request_headers['Referer'] = get_uri.to_s
                    get_uri = URI(newurl)
    
                end
            else
                found = true #resp was 404, etc
            end
      
        
        end #until
        
        return get_response   
    end
end
