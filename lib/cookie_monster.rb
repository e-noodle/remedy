class CookieMonster

  attr_accessor :jar, :cookie_store, :store_name
  

  def initialize
      
    @store_name        = "remedy"     
    @cookie_store            = PStore.new("cookies.pstore") 
    
    @cookie_store.transaction do
        if @cookie_store[@store_name.to_sym].nil? 
             @jar = CookieJar::Jar::new 
             @cookie_store[@store_name.to_sym] = @jar
        else
             @jar = @cookie_store[@store_name.to_sym]   
        end 
                    
    end 
  end 
  
  
  def get_cookie_header(uri)
  
     begin
       
        include_cookies = []
        @jar.get_cookies(uri.to_s).each { |cookie|  
                    
            if cookie.should_send? uri, false
               include_cookies << "#{cookie.name}=#{cookie.value}"     
            end    
        }
        return include_cookies.join("; ")+";"
        
     rescue Exception => e
        puts "ERR: Something went wrong getting cookie header#{e}"
     end
  end
  
  
  
  def get_cookie_value(uri, name)
  
    begin
        
        @jar.get_cookies(uri.to_s).each { |cookie|  
                    
            if cookie.should_send? uri, false
               if cookie.name == name
                   return "#{cookie.value}"
               end         
            end    
        }
        
    rescue Exception => e
        puts "ERR: Something went wrong with get_cookie_value #{e}"
    end
  end
  
  
  
  def get_response_cookies(response, uri, jar)
  
    return jar if response.get_fields('set-cookie').nil?
    
    response.get_fields('set-cookie').each{ |cookie|
    
        response_cookie = {}
        
        cookie.split(";").collect{ |i| i.strip }.each{ |c|   
            
            response_cookie[:domain] = "#{uri.host}" 
            
            case c
            when /Path=(.*)/
              #puts "Path: #{$1}"
              response_cookie[:path] = "#{$1}"
            when /Secure/
              #puts "Secure: true"
              response_cookie[:secure] = true
            when /HttpOnly/
              #puts "http_only: true"
              response_cookie[:http_only] = true
            when /Expires=(.*)/
              #puts "expires: #{$1}"
              #response_cookie[:expiry]=$1
              next
            when /Max-Age=(.*)/
              #puts "expires: #{$1}"
              next
              response_cookie[:max_age] = $1.to_i
            when /Version=(.*)/
              #puts "expires: #{$1}"
              response_cookie[:version] = $1
            when /(.*)=(.*)/
              #puts "name: #{$1}"
              response_cookie[:name] = $1
              #puts "value: #{$2}"
              response_cookie[:value] = $2
            end
            
        }
        
        
        new_cookie = CookieJar::Cookie.new(response_cookie)
        @jar.add_cookie( new_cookie )
        
    }
       
  
  end
  
  
  def get_cookie_jar
    @cookie_store.transaction do
        unless @cookie_store[@store_name.to_sym].nil?
             @jar = @cookie_store[@store_name.to_sym]
        end
    end
  end
  
  
  def get_jar
    return @jar
  end
  
  
  def save_cookies
    @cookie_store.transaction do    
      @cookie_store[@store_name.to_sym] = @jar  
    end
    
  end
   
end