#!/opt/puppet/bin/ruby

# author:  joseph rasmussen
# url:     https://github.com/e-noodle/remedy

$LOAD_PATH.unshift("#{File.dirname(__FILE__)}")

##########################################
#  Libs
##########################################

require 'net/http'
require 'open-uri'
require 'cookiejar'
require 'time'
require 'yaml'
require 'json'
require 'pstore'
require 'nokogiri'
require 'openssl'
require 'lib/session'         # custom
require 'lib/cookie_monster'  # custom
require 'lib/url'             # custom

##########################################
# globals
##########################################

logs            = ""
env_config = {}

##########################################
# get remedy config
##########################################

if File.exists?("config.yaml")
    env_config = YAML.load(IO.read("config.yaml"))
else
    puts <<-EOF.gsub(/^\s+/,"")
ERROR: Unable to get Remedy endpoint or login details.
       Check config.yaml exists in the path.

Example config.yaml:

---
remedy_url: 'https://remedy7prd.internal.company.com'
user_account: 'remedy_userid'
user_password: 'encryptedsecret'
#user_passwd_enc: false # true by default
EOF

    exit 1
end

remedy_url    = env_config['remedy_url']
remedy_uri    = URI(remedy_url)
remedy_host   = remedy_uri.host
user_account  = env_config['user_account']
user_password = env_config['user_password']

login_data = {
    'username'     => user_account,
    'pwd'          => user_password,
    'auth'         => '',
    'timezone'     => 'AET',
    'encpwd'       => '1',
    'goto'         => '',
    'server'       => '',
    'ipoverride'   => '0',
    'initialState' => '0',
    'returnBack'   => '/arsys/',
}

cache_urls = {
   :incident => {
       :cache_id    => '5bf31a2a',
       :path        => '/arsys/forms/remedy7prd-arsys/HPD%3AHelp+Desk+Classic/Default+User+View/',
       :smethod     => 'POST'
   },
   :asset => {
       :cache_id    => 'afb483',
       :path        => '/arsys/forms/remedy7prd-arsys/AST%3AComputerSystem/Management/',
       :smethod     => 'POST'
   },
   :change_request => {
       :cache_id    => '9d0040dc',
       :path        => '/arsys/forms/remedy7prd-arsys/CHG%3AInfrastructure+Change+Classic/Default+User+View/',
       :smethod     => 'GET'
   },
   :override => {
       :cache_id    => 'fb8677ad',
       :path        => '/arsys/forms/remedy7prd-arsys/AR+System+Customizable+Home+Page/Default+Administrator+View/' ,
       :smethod     => 'GET'
   }
}

headers_defaults = {
    'Origin'                  => "#{remedy_uri.scheme}://#{remedy_uri.host}",
    'Host'                    => remedy_uri.host,
    'Accept-Encoding'         => 'gzip, deflate',
    'Accept-Language'         => 'en-US,en;q=0.8',
    'User-Agent'              => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.71 Safari/537.36',
    'Connection'              => 'keep-alive'
}

search_request_headers = {
    'Content-type'            => "text/plain; charset=UTF-8",
    'Accept'                  => '*/*',
    'AtssoRedirectStatusCode' => 278
}

##########################################
# functions
##########################################

def usage
    puts "   usage:   #{__FILE__} <Incident Ref> <Asset CID> <Change Request ID>"
    puts "   example: #{__FILE__} INC000088888888 itgsydsrv000 CRQ000000999999"
end

def logger(msg, log_file = "remedy_script.log")
  IO.write(log_file,msg,mode: 'a')
end

def override_login(sToken, req_url, monster)

    # build data to override session login
    data = {
          'param'  => '15/SetOverride/1/1',
          'sToken' => sToken
    }

    req_uri                      = URI(req_url)
    uri                          = URI("#{req_uri.scheme}://#{req_uri.host}/arsys/BackChannel/")
    uri.query                    = "param=#{data['param']}&sToken=#{sToken}"
    https                        = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl                = true
    https.verify_mode            = OpenSSL::SSL::VERIFY_NONE
    override_request             = Net::HTTP::Get.new(uri.request_uri)

    headers = {
        'Origin'                    => "#{uri.scheme}://#{uri.host}",
        'Accept-Encoding'           => 'gzip, deflate, sdch',
        'Host'                      => uri.host,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.71 Safari/537.36',
        'Accept'                    => '*/*',
        'Accept-Language'           => 'en-US,en;q=0.8',
        'AtssoRedirectStatusCode'   => 278,
        'AtssoReturnLocation'       => req_url,
        'Connection'                => 'keep-alive',
        'Content-type'              => 'text/plain; charset=UTF-8',
        'Referer'                   => req_url
    }

    # add headers to the request
    request_header               = {}
    request_header['Cookie']     = monster.get_cookie_header(uri)
    request_header.each {  |header,value|
        override_request["#{header}"] = "#{value}"
    }
    headers.each{ |k,v|
        override_request[k] = v
    }

    # submit request and log
    logs = ""
    https.set_debug_output(logs)
    response = https.request(override_request)
    logger(logs)

    # get cookies and save
    monster.get_response_cookies(response, uri, monster.jar)
    monster.save_cookies
end

def download_cache(url, monster)
    cache_uri = URI(url)
    req_header = {
        'Cookie'                      => monster.get_cookie_header(cache_uri),
        'Accept-Encoding'             => 'gzip, deflate, sdch',
        'Upgrade-Insecure-Requests'   => '1',
        'Content-Type'                => 'application/x-www-form-urlencoded',
        'Accept'                      => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Cache-Control'               => 'max-age=0',
        'Referer'                     => "#{cache_uri.scheme}://#{cache_uri.host}/arsys/shared/login.jsp?/arsys/"
    }

    headers_defaults = {
        'Origin'                      => "#{cache_uri.scheme}://#{cache_uri.host}",
        'Host'                        => cache_uri.host,
        'Accept-Encoding'             => 'gzip, deflate',
        'Accept-Language'             => 'en-US,en;q=0.8',
        'User-Agent'                  => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.71 Safari/537.36',
        'Connection'                  => 'keep-alive'
    }
    http_reponse = Url.new.get(cache_uri.to_s, req_header.merge!(headers_defaults), monster )
end


def create_json_map(cache_id)
    json_map = {}
    npage    = Nokogiri::HTML(open("?cacheid="+cache_id.to_s))
    npage.css('div').each{ |item|

        key    = item['id'].to_s.strip.chomp.to_sym
        labels = item.children.select{ |i| i.name = 'label' }
        labels.collect!{ |l| l.text.to_s.chomp.strip }

        if value = labels[1]
          json_map[ key ] = value.encode("UTF-8")
        end
    }
    return json_map
end

def search_item(sToken, monster, remedy_uri, headers = {}, default_headers = {}, data_post_data, search_item, smethod)

    search_inc_url    = "#{remedy_uri.scheme}://#{remedy_uri.host}/arsys/BackChannel/"
    search_inc_uri    = URI(search_inc_url)
    timestamp_ms      = (Time.now.to_f * 1000).to_i
    url_tool          = Url.new

    # post data
    param             = data_post_data.gsub("${timestamp_ms}", timestamp_ms.to_s).gsub("${search_item}", search_item)
    data              = { 'param' => param, 'sToken' => sToken }
    # set headers
    headers['Cookie'] = monster.get_cookie_header(search_inc_uri)
    default_headers.merge!(headers)

    case smethod
    when /POST/
      search_inc_response = url_tool.postUrl_with_cookies(search_inc_url, monster, default_headers, data)
      monster.get_response_cookies(search_inc_response, search_inc_url, monster.jar); monster.save_cookies
    else
      search_inc_response = url_tool.getUrl_with_cookies(search_inc_url, monster, default_headers, data)
      monster.get_response_cookies(search_inc_response, search_inc_url, monster.jar); monster.save_cookies
    end

    return url_tool.process_http_response(search_inc_response)

end

def search_ci_asset(sToken, monster, remedy_uri, headers = {}, default_headers = {}, asset)

    search_inc_url    = "#{remedy_uri.scheme}://#{remedy_uri.host}/arsys/BackChannel/"
    search_inc_uri    = URI(search_inc_url)
    timestamp_ms      = (Time.now.to_f * 1000).to_i
    url_tool          = Url.new

    # post data
    data_post_data=<<-EOS.gsub(/\n|^[\t\s]+/, '')
        344/GetQBETableEntryList/16/remedy7prd-arsys18/AST:ComputerSystem10/Management4/102016/
        remedy7prd-arsys18/AST:ComputerSystem0/1/01/02/0/0/2/0/2/0/2/0/59/5/7/30001009/20000002
        09/40012740010/100000512410/100000512563/5/18/BMC_COMPUTERSYSTEM12/${CI_ASSET}9/BMC.ASS
        ET5/180005/1800017/5/1/41/41/41/71/70/9/3009073001/013/${timestamp_ms}0/2/0/2/0/2/0/2/0
        /
EOS
    param             = data_post_data.gsub("${timestamp_ms}", timestamp_ms.to_s).gsub("${CI_ASSET}", asset)
    data              = { 'param' => param, 'sToken' => sToken }
    # set headers
    headers['Cookie'] = monster.get_cookie_header(search_inc_uri)
    headers.merge!(default_headers)
    # get response
    search_inc_response = url_tool.postUrl_with_cookies(search_inc_url, monster, headers, data)
    # set cookies
    monster.get_response_cookies(search_inc_response, search_inc_url, monster.jar); monster.save_cookies

    return url_tool.process_http_response(search_inc_response)

end


def search_incident(sToken, monster, remedy_uri, headers = {}, default_headers = {}, incident)

    search_inc_url    = "#{remedy_uri.scheme}://#{remedy_uri.host}/arsys/BackChannel/"
    search_inc_uri    = URI(search_inc_url)
    inc_number        = incident
    timestamp_ms      = (Time.now.to_f * 1000).to_i
    url_tool          = Url.new

    # post data
    data_post_data=<<-EOS.gsub(/\n|^[\t\s]+/, "")
		1848/GetQBETableEntryList/16/remedy7prd-arsys21/HPD:Help Desk Classic17/Default User View4/102016/
		remedy7prd-arsys21/HPD:Help Desk Classic0/1/01/09/2/1/02/-10/2/0/2/0/2/0/268/23/7/30009007/3003400
		9/3012669009/3012670009/3012907009/3012910009/3013986009/3013989009/3013990009/3027964009/30283130
		09/3030216009/3034976009/3035300009/30405100010/100000016110/100000039710/100000039810/10000006871
		0/100000068810/100000368410/100000512410/10000051251280/23/3/INC9/BMC.ASSET15/${inc_number}3/INC25
		/AST:AssetPeople_AssetBase29/AST:CMDBAssoc CI UA CMDBAssoc24/8000 General Information4/1 No10/0 In
		ternal9/1087776007/0 Never5/1 Yes15/Internet E-mail15/Internet E-mail993/ AND ( ('112' LIKE "%;100
		0001591;%") OR ('112' LIKE "%;1000001590;%") OR ('112' LIKE "%;1000001268;%") OR ('112' LIKE "%;81
		2;%") OR ('112' LIKE "%;20020;%") OR ('112' LIKE "%;20032;%") OR ('112' LIKE "%;20012;%") OR ('112
		' LIKE "%;1000000834;%") OR ('112' LIKE "%;20004;%") OR ('112' LIKE "%;20302;%") OR ('112' LIKE "%
		;20031;%") OR ('112' LIKE "%;20502;%") OR ('112' LIKE "%;20007;%") OR ('112' LIKE "%;20003;%") OR
		('112' LIKE "%;808;%") OR ('112' LIKE "%;20056;%") OR ('112' LIKE "%;20019;%") OR ('112' LIKE "%;2
		0000;%") OR ('112' LIKE "%;20352;%") OR ('112' LIKE "%;1000000007;%") OR ('112' LIKE "%;20055;%")
		OR ('112' LIKE "%;14451;%") OR ('112' LIKE "%;20315;%") OR ('112' LIKE "%;802;%") OR ('112' LIKE "
		%;20354;%") OR ('112' LIKE "%;442;%") OR ('112' LIKE "%;440;%") OR ('112' LIKE "%;441;%") OR ('112
		' LIKE "%;13005;%") OR ('112' LIKE "%;20403;%") OR ('112' LIKE "%;20316;%") OR ('112' LIKE "%;2031
		3;%") OR ('112' LIKE "%;13006;%") OR ('112' LIKE "%;804;%") OR ('112' LIKE "%;803;%"))15/${inc_num
		ber}1/01/35/180005/1800017/Default User View5/180005/1800072/23/1/41/41/41/41/41/41/61/61/61/71/61
		/61/41/41/41/41/21/21/71/71/41/71/70/9/3999900881/013/${timestamp_ms}0/2/0/2/0/2/0/2/0/
EOS

    param             = data_post_data.gsub("${timestamp_ms}", timestamp_ms.to_s).gsub("${inc_number}", inc_number)
    data              = { 'param' => param, 'sToken' => sToken }
    # set headers
    headers['Cookie'] = monster.get_cookie_header(search_inc_uri)
    headers.merge!(default_headers)
    # get response
    search_inc_response = url_tool.postUrl_with_cookies(search_inc_url, monster, headers, data)
    # set cookies
    monster.get_response_cookies(search_inc_response, search_inc_url, monster.jar); monster.save_cookies

    return url_tool.process_http_response(search_inc_response)

end


def check_remedy_result(response, sToken, monster, remedy_uri)
    unless response =~ /this\.result\=/
      case response =~ /(retry\=this\.Override)|(urWFC\.status)/
      when /urWFC\.status/
        puts "urWFC.status\n#{$1}"
      when /retry\=this\.Override/
        puts "retry\=this\.Override\n#{$1}"
      else
        case response
        when /User\ is\ currently\ connected\ from\ another/
          override_login(sToken, "#{remedy_uri.scheme}://#{remedy_uri.host}/arsys/forms/remedy7prd-arsys/AR+System+Customizable+Home+Page/Default+Administrator+View/?cacheid=fb8677ad" ,monster)
          puts "Error: User\ is\ currently\ connected\ from\ another session. Please try again"
          exit 1
        end
      end
    end
end

def filter_results_and_print(results_array_mapped, title)
    results_hash = {}
    # filter results by rejecting items without mappings or null values
    results_array_mapped.reject!{ |item| item[:name].nil? or item[:v].nil? }
    results_array_hashes_mapped = results_array_mapped.collect{|item| { item[:name] => item[:v] } }
    results_array_hashes_mapped.each{ |item|
        item.each{ |k,v|
            results_hash[k.to_sym] = v.to_s
        }
    }
    # prnt sorted results
    puts "---------------------------------------"
    puts "REMEDY ARS: %s" % title
    puts "---------------------------------------\n\n"
    results_hash.sort_by{ |key, value| key  }.each{|k,v|
        if k.to_s.match(/Date/)
            v = Time.at(v.to_i).strftime('%Y-%m-%d %H:%M:%S') # convert date
        end
        printf("%-35s = %-20s\n" % [k.to_s, "#{v.to_s.gsub('"', '').gsub(/^\s+/, '').gsub(/\s+$/, '').strip.chomp}"], 20)
    }

end

def get_array_from_response_crq(res_out)

    results_array       = []  # array to store hashes
    res_out             =~ /^.*this.*result\=(.*)\]\,eid\:.*$/
    res_out_match_data  = $1.match(/.*n\:[0-9]+,start\:0,e\:\[\{(.*)\}$/) unless $1.nil?

    unless res_out_match_data.nil?
        $1.split("\},\{").each{ |item_a|
           temp_item = {}
           item_a.split(",").each{ |item_b| k,v = item_b.split(":")
              temp_item[k.to_sym]=v
           }
           results_array.push(temp_item)
        }
    end
    return results_array
end


def get_array_from_response(res_out)

    # array to store hashes

    results_array     = []
    res_out       =~ /^.*this.*result\=(.*)\]\,eid\:.*$/
    res_out_match_data  = $1.match(/.*n\:[0-9]+,start\:0,e\:\[{(.*)\}$/) unless $1.nil?

    unless res_out_match_data.nil?
        $1.split("\},\{").each{ |item_a|
           temp_item = {}
           item_a.split(",").each{ |item_b|
               k,v = item_b.split(":")
               temp_item[k.to_sym]=v
           }
           results_array.push(temp_item)
        }
    end
    return results_array
end

def map_results_array(results_array, json_map)

    results_array_mapped = []

    results_array.each{ |item|

        store_item = {}
        item.each{ |key,val|
            store_item[key.to_sym] = val.to_s

            next if "#{val}" == "\"\"" or val.nil? or val.to_i < 10000
            next if "#{key}" == "\"\"" or key.nil?

            json_map.each{ |k,v|
                if k.to_s.match(/^WIN_0_#{val.to_s}$/)
                  store_item[:name]=v.to_s
                end
            }
        }
        results_array_mapped.push(store_item)
    }
    return results_array_mapped
end

class String
    def remove_non_ascii
        self.encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => "ASCII")
    end
end

################
# main routine
################


# check login to remedy

login_url                   = "#{remedy_uri.scheme}://#{remedy_uri.host}/arsys/shared/login.jsp?/arsys/home/"
login_uri                   = URI(login_url)

monster                     = CookieMonster.new
session                     = Session.new(user_account)
url_tool = Url.new

request_header_defaults = {
    'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.71 Safari/537.36'
}

# check if a session already exists to reuse before attempting to login

unless monster.get_cookie_header(login_uri).match(/.*SESSION.*/)

    login_response = url_tool.get(login_url, request_header_defaults, monster)

    monster.get_response_cookies(login_response, login_uri, monster.get_jar)
    monster.save_cookies

    # attempt to login with user account web form

    user_login_url                   = "#{remedy_uri.scheme}://#{remedy_uri.host}/arsys/servlet/LoginServlet"
    user_login_uri                   = URI(user_login_url)
    user_login_request_header = {
        'Cookie'                        => monster.get_cookie_header(user_login_uri),
        'Origin'                        => "https://#{remedy_uri.host}",
        'Host'                          => user_login_uri.host,
        'Accept-Encoding'               => 'gzip, deflate, sdch',
        'Accept-Language'               => 'en-US,en;q=0.8',
        'Upgrade-Insecure-Requests'     => '1',
        'User-Agent'                    => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.71 Safari/537.36',
        'Content-Type'                  => 'application/x-www-form-urlencoded',
        'Accept'                        => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Cache-Control'                 => 'max-age=0',
        'Referer'                       => "#{remedy_uri.scheme}://#{remedy_uri.host}/arsys/shared/login.jsp?/arsys/",
        'Connection'                    => 'keep-alive',
    }

    # submit form and get response
    user_login_response = postUrl_with_cookies(user_login_url, monster, user_login_request_header, login_data)


    ###################
    # Follow Redirect
    ###################

    fail unless user_login_response.code == '302'
    logger("Redirecting to: %s" % user_login_response.get_fields('location').first)

    # Save cookies

    monster.get_response_cookies(user_login_response, user_login_uri, monster.jar)
    monster.save_cookies


    case user_login_response
    when Net::HTTPSuccess
        # do nothing
    when Net::HTTPRedirection
        http_redirect = Url.new
        http_reponse  = http_redirect.get(user_login_response.get_fields('location').first, user_login_request_header.reject{ |k,v| k =~ /^Cookie$/}, monster )
    else
        puts "Exception(al)"
        exit 1
    end

    monster.get_response_cookies(user_login_response, user_login_uri, monster.jar)
    monster.save_cookies


end # end unless

###########################
# get a session token
###########################

# get token from session
session.get_session_id if session.session_id.nil?

# if session token is empty request a new token
if session.session_id.nil?

    token_headers = {
        'Origin'                  => "https://#{remedy_uri.host}",
        'Host'                    => remedy_uri.host,
        'Accept-Encoding'         => 'gzip, deflate',
        'Accept-Language'         => 'en-US,en;q=0.8',
        'User-Agent'              => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.71 Safari/537.36',
        'Connection'              => 'keep-alive'
    }

    sToken      = nil

    token_url   = "#{remedy_uri.scheme}://#{remedy_host}/arsys/forms/remedy7prd-arsys/SHR:OverviewConsole/Overview%20Homepage%20Content/udd.js?format=html&w=&"
    token_res   = handle.process_http_response(Url.new.get(token_url, token_headers , monster ))

    res_match   =  token_res =~ /sTok=\"(.*)\"/

    unless $1.nil?
      sToken = $1
      session.session_id = sToken
      session.set_session_id
    end
else
  # store stoken
  sToken = session.session_id
end


####################
# main routine
####################

# check input arguments are correct

if ARGV.reject{ |input| input.match(/INC|itg|bfs|uhkg|CRQ/)}.size > 0
    usage
    exit 1
end

ARGV.each{|a|

  case a.to_s
  when /INC/
    incident = a.to_s

    # download cache maps
    cache_url = "#{remedy_uri.scheme}://#{remedy_uri.host}#{cache_urls[:incident][:path]}?cacheid=#{cache_urls[:incident][:cache_id]}"
    download_cache(cache_url, monster)
    json_map_inc                   = create_json_map( cache_urls[:incident][:cache_id] )

    #search & check result
    ['AtssoReturnLocation','Referer'].each{ |h| search_request_headers[h] = cache_url }
    inc_res_out                    = search_incident(sToken, monster, remedy_uri, search_request_headers, headers_defaults, incident)
    check_remedy_result(inc_res_out, sToken, monster, remedy_uri)

    # display result
    results_array_inc              = get_array_from_response(inc_res_out.remove_non_ascii)
    results_array_mapped_inc       = map_results_array(results_array_inc, json_map_inc)
    filter_results_and_print(results_array_mapped_inc, incident)

  when /itg|bfs|uhkg/
    asset_ci = a.to_s

    # download cache maps
    cache_url = "#{remedy_uri.scheme}://#{remedy_uri.host}#{cache_urls[:asset][:path]}?cacheid=#{cache_urls[:asset][:cache_id]}"
    download_cache(cache_url, monster)
    json_map_ci                   = create_json_map( cache_urls[:asset][:cache_id] )

    #search & check result
    ['AtssoReturnLocation','Referer'].each{ |h| search_request_headers[h] = cache_url }
    ci_res_out                    = search_ci_asset(sToken, monster, remedy_uri, search_request_headers, headers_defaults, asset_ci)
    check_remedy_result(ci_res_out, sToken, monster, remedy_uri)

    # display result
    results_array_ci              = get_array_from_response(ci_res_out)
    results_array_mapped_ci       = map_results_array(results_array_ci, json_map_ci)
    filter_results_and_print(results_array_mapped_ci, asset_ci)
  when /CRQ/
    asset_crq = a.to_s

    # download cache maps
    cache_url = "#{remedy_uri.scheme}://#{remedy_uri.host}#{cache_urls[:change_request][:path]}?cacheid=#{cache_urls[:change_request][:cache_id]}"
    download_cache(cache_url, monster)
    json_map_crq                  = create_json_map(cache_urls[:change_request][:cache_id])

    #search & check result
    data_post_data=<<-EOS.gsub(/\n|^[\t\s]+/, '')
		502/GetQBETableEntryList/16/remedy7prd-arsys33/CHG:Infrastructure Change Classic17/Default User View4
		/102016/remedy7prd-arsys33/CHG:Infrastructure Change Classic0/1/01/02/0/0/2/0/2/0/2/0/65/6/7/30006007
		/30034008/100000019/3012669009/30172560010/100000018276/6/3/CRQ9/BMC.ASSET25/CHG:Infrastructure Chang
		e3/CRQ5/0 Yes15/${search_item}20/6/1/41/41/41/41/61/40/9/3999900881/013/${timestamp_ms}27/Change ID*+
		=${search_item}25/2/8/1000000110/100000018248/2/25/CHG:Infrastructure Change15/${search_item}2/0/2/0/
EOS
    ['AtssoReturnLocation','Referer'].each{ |h| search_request_headers[h] = cache_url }
    crq_res_out = search_item(sToken, monster, remedy_uri, search_request_headers, headers_defaults, data_post_data, asset_crq, "GET")

    # display result
    results_array_crq             = get_array_from_response_crq(crq_res_out.remove_non_ascii)
    results_array_mapped_crq      = map_results_array(results_array_crq, json_map_crq)
    filter_results_and_print(results_array_mapped_crq, asset_crq)
  else
    usage
  end
}

