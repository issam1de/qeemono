#
# (c) 2011, Mark von Zeschau
#


module Qeemono
  #
  # The manager for all clients (web sockets).
  #
  # Clients can be assigned to resp. unassigned
  # from modules. See assign_to_modules method
  # for detailed information.
  #
  class ClientManager

    def initialize(server_interface)
      @qsif = server_interface
      @qsif[:client_manager] = self

      @anonymous_client_id = 0

      @web_sockets = {} # key = client id; value = web socket object
      @clients = {} # key = web socket signature; value = client id (the reverse of @web_sockets for fast access)

      @modules = {} # key = client id; value = array of module symbols
    end

    #
    # Returns web socket object (aka client) filtered by the given conditions hash.
    #
    # conditions:
    #   * :client_id - (symbol) - The client id of the client (web socket) to be returned
    #
    def web_socket(conditions = {})
      @web_sockets[conditions[:client_id]]
    end

    #
    # Returns the modules the given client id is assigned to.
    #
    # Only message handlers belonging to the :core module or
    # belonging to at least one module also the client belongs
    # to are available to (callable by) the client.
    #
    def modules(client_id)
      @modules[client_id.to_sym] || []
    end

    #
    # This method is only used internally.
    #
    # This is the first thing what happens when a client connects to the qeemono
    # server.
    #
    # Extracts the client id (which must be persistently stored on client-side) from
    # the given web socket and returns it as symbol. Additionally, the web socket is
    # associated with this client id so that the web socket also can be identified
    # by the client id.
    #
    # Since web sockets are not session aware and therefore can change over time (e.g.
    # when the refresh button of the browser was hit) the web socket/client association
    # has to be updated/refreshed in order that the client id always points to the
    # current web socket for the resp. client.
    #
    # If no client id is given (contained in the web socket) a unique anonymous client
    # id is generated and associated instead.
    #
    # If a client tries to steal another client's session (by passing the same client
    # id) a unique anonymous client id is generated and associated instead.
    #
    def bind(web_socket)
      client_id = web_socket.request['Query']['client_id'] # Extract client_id from web socket
      new_client_id = nil

      if client_id.nil? || client_id.to_s.strip == ''
        new_client_id = anonymous_client_id(web_socket)
        notify(:type => :warn, :code => 7000, :receivers => web_socket, :params => {:new_client_id => new_client_id, :wss => web_socket.signature})
      else
        # Client id must be a symbol...
        client_id = client_id.to_sym
      end

      if session_hijacking_attempt?(web_socket, client_id)
        new_client_id = anonymous_client_id(web_socket)
        notify(:type => :error, :code => 7010, :receivers => web_socket, :params => {:client_id => client_id, :new_client_id => new_client_id, :wss => web_socket.signature})
      end

      if client_id == Notificator::SERVER_CLIENT_ID
        new_client_id = anonymous_client_id(web_socket)
        notify(:type => :error, :code => 7020, :receivers => web_socket, :params => {:new_client_id => new_client_id, :wss => web_socket.signature})
      end

      client_id = new_client_id if new_client_id

      # Remember the web socket for this client (establish the client/web socket association)...
      @web_sockets[client_id] = web_socket
      @clients[web_socket.signature] = client_id

      return client_id
    end

    #
    # This method is only used internally.
    #
    # This is the last thing what happens when a client disconnects
    # from the qeemono server (e.g. caused by browser refresh).
    #
    # Unbinds (forgets) the association between the given web socket
    # and its client. For more information read the documentation of
    # method bind.
    #
    # Returns the client id of the just unbound association or nil
    # if there was no client associated to the given web socket.
    #
    def unbind(web_socket)
      # OBSOLETE ::: client_id_to_forget, _web_socket = @web_sockets.rassoc(web_socket)
      client_id_to_unbind = @clients[web_socket.signature]
      if client_id_to_unbind
        @qsif[:channel_manager].unsubscribe(client_id_to_unbind, ChannelManager::ALL_CHANNELS_SHORTCUT)
        @web_sockets.delete(client_id_to_unbind)
        @clients.delete(web_socket.signature)
        return client_id_to_unbind
      end
    end

    #
    # Assigns the given client id to the given modules.
    #
    # Each client can only access/call those message
    # handlers which belong to at least one module the
    # respective client also belongs to.
    # In other words, as long as a certain client and a
    # certain message handler share (are assigned to)
    # the same module(s) (at least one), they are defined
    # to be 'known' to each other. Thus, the client is
    # able to access/call the resp. message handler.
    # Core message handlers (they belong to the :core
    # module) are always and automatically accessible/
    # callable by any client (without requiring them to
    # belong to the :core module).
    #
    def assign_to_modules(client_id, modules)
      receiver = @qsif[:client_manager].web_socket(:client_id => client_id)

      modules ||= []
      modules = [modules] unless modules.is_a? Array
      if modules.empty?
        notify(:type => :error, :code => 3100, :receivers => receiver, :params => {:client_id => client_id})
        return false
      end

      @modules[client_id] ||= []

      modules.each do |the_module|
        params = {:client_id => client_id, :module_name => the_module}

        if !Qeemono::Util::CommonUtils.non_empty_symbol(the_module.to_sym)
          notify(:type => :error, :code => 3110, :receivers => receiver, :params => {:client_id => client_id})
        else
          module_symbol = the_module.to_sym
          if @modules[client_id].include?(module_symbol)
            notify(:type => :error, :code => 3010, :receivers => receiver, :params => params)
          else
            @modules[client_id] << module_symbol
            notify(:type => :debug, :code => 3000, :receivers => receiver, :params => params)
          end
        end
      end

      return true
    end

    #
    # Unassigns the given client id from the given modules.
    #
    # See assign_to_modules method for detailed information.
    #
    def unassign_from_modules(client_id, modules)
      receiver = @qsif[:client_manager].web_socket(:client_id => client_id)

      modules ||= []
      modules = [modules] unless modules.is_a? Array
      if modules.empty?
        notify(:type => :error, :code => 3120, :receivers => receiver, :params => {:client_id => client_id})
        return false
      end

      @modules[client_id] ||= []

      modules.each do |the_module|
        params = {:client_id => client_id, :module_name => the_module}

        if !Qeemono::Util::CommonUtils.non_empty_symbol(the_module.to_sym)
          notify(:type => :error, :code => 3130, :receivers => receiver, :params => {:client_id => client_id})
        else
          module_symbol = the_module.to_sym
          if !@modules[client_id].include?(module_symbol)
            notify(:type => :error, :code => 3030, :receivers => receiver, :params => params)
          else
            @modules[client_id].delete(module_symbol)
            notify(:type => :debug, :code => 3020, :receivers => receiver, :params => params)
          end
        end
      end

      return true
    end

    protected

    #
    # Generates and returns a unique client id (symbol) for
    # the given web socket object. This is used if a client
    # does not submit its client id.
    #
    # If an anonymous client id has already been generated
    # for the given web socket object earlier, it is just
    # returned; otherwise a new anonymous client id is
    # generated (and returned).
    #
    def anonymous_client_id(web_socket)
      @clients[web_socket.signature] || "__anonymous-client-#{(@anonymous_client_id += 1)}".to_sym
    end

    #
    # Returns true if there is already stored another web socket
    # object for the same client id; false otherwise.
    #
    def session_hijacking_attempt?(web_socket, client_id)
      older_web_socket = @qsif[:client_manager].web_socket(:client_id => client_id)
      return true if older_web_socket && older_web_socket.object_id != web_socket.object_id
      return false
    end

    private

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end
end
