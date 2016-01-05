class Url
      
    attr_accessor :max_attempts, :attempts, :user_agent, :headers_defaults 

    # Create an instance of this class
    def initialize 
        @attempts       = 0
        @max_attempts   = 30        
        @headers_defaults = {   
            'Origin'            => "https://#{remedy_host}",
            'Host'              => remedy_host,
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
 
    def getUrl_with_cookies(get_url, cookie_monster, get_request_headers = nil) 

    
        logs = ""

        get_url                 = get_url
        get_uri                 = URI(get_url)
        get_https               = Net::HTTP.new(get_uri.host,get_uri.port)
        
        if get_uri.instance_of? URI::HTTPS
            get_https.use_ssl       = true
            get_https.verify_mode   = OpenSSL::SSL::VERIFY_NONE
        end
        
        get_https.set_debug_output(logs); logger(logs)
        
        get_request               = Net::HTTP::Get.new(get_uri.path)
        get_request_headers.merge!(@headers_defaults)
        get_request.initialize_http_header(get_request_headers)
        
        get_request['Cookie']     = cookie_monster.get_cookie_header(get_uri)
        
        
        
        get_response  = get_https.request(get_request)
        logger(logs)

        cookie_monster.get_response_cookies(get_response, get_uri, cookie_monster.jar)
        cookie_monster.save_cookies 
        
        return get_response
    end
 
  
    def postUrl_with_cookies(post_url, cookie_monster, post_request_headers = nil) 

        post_url               = post_url
        post_uri               = URI(post_url)
        post_https             = Net::HTTP.new(post_uri.host,post_uri.port)
        
        if post_uri.instance_of? URI::HTTPS
            post_https.use_ssl      = true
            post_https.verify_mode  = OpenSSL::SSL::VERIFY_NONE
        end
  
        post_request           = Net::HTTP::Post.new(post_uri.path)
        
        post_request_headers.merge!(@headers_defaults)
        unless post_request_headers.nil?
            post_request_headers.each{ |k,v| post_request[k] = v }   
        end   
        
        # add cookies / todo: post from session
        
        post_request['Cookie'] = cookie_monster.get_cookie_header(post_uri)

        logs = ""
        post_https.set_debug_output(logs)
        
        post_response = post_https.request(post_request)
        
        logger(logs)

        cookie_monster.get_response_cookies(post_response, post_uri, cookie_monster.jar)
        cookie_monster.save_cookies
        
        return post_response
    end
  
  
    def get(url, headers, cookie_monster)
 
        return nil if url.nil?    
        
        found     = false
        attempts  = 0 
        resp      = nil       
        uri       = URI(url)
        

        until( found || attempts >= @max_attempts)
             
            attempts            += 1
            
            
            http                = Net::HTTP.new(uri.host,uri.port)
            http.open_timeout   = 10
            http.read_timeout   = 10
            
            path                = uri.path
            path                = "/" if path == ""
            path                = "#{path}?#{uri.query}" unless uri.query.nil?
          
          
            req = Net::HTTP::Get.new(path,{'User-Agent' => @user_agent}) 
            
            if uri.instance_of? URI::HTTPS
                http.use_ssl      = true
                http.verify_mode  = OpenSSL::SSL::VERIFY_NONE
            end 
          
            headers['Cookie'] = cookie_monster.get_cookie_header(uri)           

            req.initialize_http_header(headers)
            resp = http.request(req)
            
            #resp = self.getUrl_with_cookies("https://"+uri.host+path, cookie_monster, headers) 
             
            case resp
            when Net::HTTPSuccess
                if resp.code == "200"
                    page = process_http_response(resp)        
                    IO.write("?#{uri.query}", page) unless page.nil?    
                    resp.header['Referer'] = uri.to_s              
                    return resp                
                end
            when Net::HTTPRedirection
                
                if (resp.header['location'] != nil)          
                    newurl = URI.parse(resp.header['location'])               
                    
                    if(newurl.relative?)
                        newurl = url+resp.header['location']
                    end   

                    if File.exists?("?#{uri.query}")
                      file = File.stat "?#{uri.query}"
                      headers['If-Modified-Since']  = file.mtime.rfc2822
                    end
                    
                    headers['Referer'] = uri.to_s
                    uri = URI(newurl)
    
                end
            else
                found = true #resp was 404, etc
                #logger(logs)
            end
      
        
        end #until
        
        return resp   
    end
end