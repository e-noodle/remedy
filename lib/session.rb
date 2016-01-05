class Session

  attr_accessor :session_id, :session_store, :session_name
  

  def initialize(user_account)
  
        @session_name         = user_account    
        @session_store            = PStore.new("sessions.pstore") 

        @session_store.transaction do

            if @session_store[@session_name.to_sym].nil? 
                 @session_id = nil 
                 @session_store[@session_name.to_sym] = @session_id
            else
                 @session_id = @session_store[@session_name.to_sym]   
            end 
                        
        end 
    
  end 
  
  
  def get_session_id
    @session_store.transaction do
        unless @session_store[@session_name.to_sym].nil?
             @session_id = @session_store[@session_name.to_sym]
        end
    end
  end
 
  def set_session_id
    @session_store.transaction do   
      @session_store[@session_name.to_sym] = @session_id  
    end
    
  end
   
end