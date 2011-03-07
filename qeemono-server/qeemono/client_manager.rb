module Qeemono
  #
  # The manager for all clients (web sockets).
  #
  class ClientManager

    def initialize(server_interface)
      @qsif = server_interface
      @qsif[:client_manager] = self

      @anonymous_client_id = 0

      @web_sockets = {} # key = client id; value = web socket object
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
    # Only message handlers belonging to the :core module and
    # belonging to modules also the client belongs to are
    # available to (callable by) the client.
    #
    def modules(client_id)
      @modules[client_id.to_sym] || []
    end

    #
    # This is the first thing what happens when client and
    # qeemono server connect.
    #
    # Extracts the client_id (which must be persistently stored on client-side) from
    # the given web socket and returns it. Additionally, the given web socket is
    # associated with its contained client id so that the web socket can be accessed
    # via the client_id.
    #
    # Since web sockets are not session aware and therefore can change over time
    # (e.g. when the refresh button of the browser was hit) the association has to be
    # refreshed in order that the client_id always points to the current web socket
    # for this resp. client.
    #
    # If no client_id is contained in the web socket an error is sent back to the
    # requesting client and false is returned. Further processing of the request is
    # ignored.
    #
    # If another client is trying to steal another client's session (by passing the
    # same client_id) an error is sent back to the requesting client and false is
    # returned. Further processing of the request is ignored.
    #
    # Returns true if everything went well.
    #
    def bind(web_socket)
      client_id = web_socket.request['Query']['client_id'].to_sym # Extract client_id from web socket
      new_client_id = nil

      if client_id.nil? || client_id.to_s.strip == ''
        new_client_id = anonymous_client_id
        notify(:type => :warn, :code => 7000, :receivers => web_socket, :params => {:new_client_id => new_client_id, :wss => web_socket.signature})
      end

      if session_hijacking_attempt?(web_socket, client_id)
        new_client_id = anonymous_client_id
        notify(:type => :error, :code => 7010, :receivers => web_socket, :params => {:client_id => client_id, :new_client_id => new_client_id, :wss => web_socket.signature})
      end

      if client_id == Notificator::SERVER_CLIENT_ID
        new_client_id = anonymous_client_id
        notify(:type => :error, :code => 7020, :receivers => web_socket, :params => {:new_client_id => new_client_id, :wss => web_socket.signature})
      end

      client_id = new_client_id if new_client_id

      # Remember the web socket for this client (establish the client/web socket association)...
      @web_sockets[client_id] = web_socket

      return client_id
    end

    #
    # This is the last thing what happens when client and
    # qeemono server disconnect (e.g. caused by browser refresh).
    #
    # Forgets the association between the given web socket and its contained client.
    # For more information read the documentation  of
    # remember_client_web_socket_association
    #
    # Returns the client_id of the unlearned association.
    #
    def unbind(web_socket)
      client_id_to_forget, _web_socket = @web_sockets.rassoc(web_socket)
      if client_id_to_forget
        @qsif[:channel_manager].unsubscribe(client_id_to_forget, :all)
        @web_sockets.delete(client_id_to_forget)
        return client_id_to_forget
      end
    end

    #
    # Assigns the given client id to the given modules.
    #
    def assign_to_modules(client_id, modules)
      modules ||= []
      modules = [modules] unless modules.is_a? Array
      if modules.empty?
        notify(:type => :error, :code => 5170, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      modules.each do |the_module|
        if the_module.nil? || the_module.to_s.strip.empty?
          notify(:type => :error, :code => 5180, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
          return false
        else
          (@modules[client_id] ||= []) << the_module.to_sym
          notify(:type => :debug, :code => 3000, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :module_names => modules.inspect})
        end
      end

      return true
    end

    #
    # Unassigns the given client id from the given modules.
    #
    def unassign_from_modules(client_id, modules)
      modules ||= []
      modules = [modules] unless modules.is_a? Array

      modules.each do |the_module|
        (@modules[client_id] ||= []).delete(the_module.to_sym)
        notify(:type => :debug, :code => 3010, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :module_names => modules.inspect})
      end

      return true
    end

    protected

    #
    # Generates and returns a unique client id.
    # Used when a client does not submit its client id.
    #
    def anonymous_client_id
      "__anonymous-client-#{(@anonymous_client_id += 1)}".to_sym
    end

    #
    # Returns true if there is already a different web socket for the same client_id;
    # false otherwise.
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
