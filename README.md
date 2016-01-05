## BMC Remedy Ruby HTTP Client

Generate INC, CRQ & Asset details by querying BMC Remedy's Midweb Tier endpoint over HTTP using a standard remedy user account and the native Net:HTTP libraries provided by Ruby (1.9.3)

*** Note this script is considered Beta (not been properly tested) use at your own risk! ***

##### References
This script was based on the VuGen scripting for BMC Remedy Action Request System 7.1 blog located at  http://www.jds.net.au/tech-tips/vugen-scripting-for-remedy/ 

#### Requires

* CookieJar
* Nokogiri
* Ruby 1.9.3
* Tested on BMC Remedy 7.1 

#### Advantages 

* does *not* require access to the Remedy API endpoint 
* does *not* require a priviledged user acccount
* minimal dependencies


#### Disadvantages 

* subject to UI changes with Remedy
* does not support javascript 
* custom script not supported
* cookies do not support max-age/expires

#### TODO

* support config.yaml
* store session and cookies in a temp location
* revert to CGI::cookie to remove dependency on CookieJar (does not support max-age/expires)

#### Install

1. Clone repo and install gems
```
$ git clone https://github.com/e-noodle/remedy.git && cd remedy
$ sudo gem install cookiejar
```
2. Update config.yaml:
```
---
remedy_url: 'https://remedy7prd.internal.company.com'
user_account: 'remedy_userid'
user_password: 'encryptedsecret'
#user_passwd_enc: false # true by default
```
3. Run and parse a space separated string containing CRQs, INCs, or CIDs (note INCs/CRQs need to have the correct number of characters or padded if necessary)
```
$ ./remedy.rb INC000099999999
```

#### Example

Query INC000099999999 details

```
$ ./remedy.rb INC000099999999
---------------------------------------
REMEDY ARS: INC000099999999
---------------------------------------

Assigned Group*+                    = Service Desk-Global
Assignee+                           = Joe Blogs
Closed Date                         = 1970-01-01 10:00:00
Closure Source                      = 2000 System
Company*+                           = Company ACME
Company+                            = Company ACME
Department                          = Sales NSW
Escalated?                          = 1 No
First Name*+                        = Tom
Impact*                             = 3000 3-Moderate/Limited
Inbound:                            = 0
Incident ID*+                       = INC000099999999
Incident Type*                      = 1 User Service Request
Last Acknowledged Date              = 1970-01-01 10:00:00
Last Name*+                         = Jones
Last Resolved Date                  = 1970-01-01 10:00:00
Manufacturer                        = End User Applications
Manufacturer (R)                    = Applications
Notes                               = Ensure user is authenticated
Operational Categorization Tier 1   = Access Management
Operational Categorization Tier 2   = Update/Modify
Operational Categorization Tier 3   = Password Reset
Organization                        = ABC
Outbound:                           = 1
Owner Group+                        = Service Desk-Global
Owner Support Company               = Company ACME
Owner Support Organization          = Support IT
Phone Number*+                      = +64 4 4444 4444
Priority*                           = 1 High
Product Categorization Tier 1       = End User Applications
Product Categorization Tier 2       = - None -
Product Categorization Tier 3       = Password Reset
Product Name (R)+                   = Help
Product Name+                       = Help
Reported Date+                      = 1970-01-01 10:00:00
Reported Source                     = 6000 Phone
Resolution                          = Solution provided to customer
Resolution Product Categorization Tier 1 = Applications
Resolution Product Categorization Tier 2 = Windows 7
Resolution Product Categorization Tier 3 = Account Administration
Responded Date+                     = 1970-01-01 10:00:00
Response                            = 0 Yes
Site+                               = L1 Seaseme PLACE
Status_Reason_Hidden                = 17000 No Further Action Required
Summary*                            = Applications Recovery
Support Company*                    = Company ACME
Support Organization*               = Support IT
Total Transfers:                    = 0
Transfers between Groups:           = 0
Transfers between Individuals:      = 0
Urgency*                            = 2000 2-High
Weight*                             = 18

```