module Qeemono
  #
  # The manager for all EventMachine channels.
  #
  class ChannelManager

    SYSTEM_CHANNELS = [:broadcast, :broadcastwb]


    def initialize(server_interface)
      @qsif = server_interface
      @qsif[:channel_manager] = self

      @channel_subscriptions = {} # key = client id; value = hash of channel symbols and channel subscriber ids {channel symbol => channel subscriber id}
      @channels = {} # key = channel symbol; value = channel object
      @channel_subscribers = {} # key = channel symbol; value = array of client ids of channel subscribers

      SYSTEM_CHANNELS.each do |system_channel|
        @channels[system_channel.to_sym] = EM::Channel.new
      end
    end

    def channel(conditions = {})
      @channels[conditions[:channel]]
    end

    #
    # Creates the given channels.
    #
    def create_channels(client_id, channel_symbols, options = {})
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array
      channel_symbols.each do |channel_symbol|
        channel_symbol = channel_symbol.to_sym
        if @channels[channel_symbol].nil?
          @channels[channel_symbol] = EM::Channel.new
          notify(:type => :debug, :code => 2040, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol})
        else
          notify(:type => :error, :code => 2053, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol})
        end
      end

    end

    #
    # Destroys the given channels and unsubscribes all
    # subscribers beforehand.
    #
    def destroy_channels(client_id, channel_symbols, options = {})
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      client_ids_to_be_unsubscribed = []
      channel_symbols.each do |channel_symbol|
        channel_symbol = channel_symbol.to_sym
        client_ids_to_be_unsubscribed << @channel_subscribers[channel_symbol] unless @channel_subscribers[channel_symbol].nil?
      end
      client_ids_to_be_unsubscribed = client_ids_to_be_unsubscribed.flatten.uniq

      client_ids_to_be_unsubscribed.each do |client_id|
        unsubscribe(client_id, channel_symbols)
      end

      channel_symbols.each do |channel_symbol|
        channel_symbol = channel_symbol.to_sym
        if SYSTEM_CHANNELS.include?(channel_symbol)
          notify(:type => :error, :code => 2051, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol})
          next
        end
        if @channels[channel_symbol]
          subscriber = @channel_subscribers[channel_symbol]
          if subscriber
            @channel_subscriptions[subscriber].delete(channel_symbol) if @channel_subscriptions[subscriber]
            @channel_subscribers.delete(channel_symbol)
          end
          @channels.delete(channel_symbol)
          notify(:type => :debug, :code => 2050, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol})
        else
          notify(:type => :error, :code => 2052, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol})
        end
      end
    end

    #
    # Subscribes the client represented by client_id to the channels represented by
    # the channel_symbols array (instead of an array also a single channel symbol
    # can be passed). Channels are created on-the-fly if not existent yet.
    #
    # Returns the channel subscriber ids (array) of all channels which just have
    # been subscribed to.
    #
    # options:
    #   * :bounce (bool) - If true, broadcasting messages to all subscribers of the given
    #                      channels (channel_symbols) includes the given client (client_id)
    #                      because it is also subscribed to the channels.
    #                      If false (the default), the client is not included (although subscribed)
    #   * :create_lazy (bool) - If true, the channel(s) is/are automatically created if not existent
    #                           yet. If false (the default), an error notification is sent back and
    #                           nothing will be done.
    #
    def subscribe(client_id, channel_symbols, options = {})
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      channel_subscriber_ids = []
      subscriptions_hash = @channel_subscriptions[client_id] ||= {}

      channel_symbols.each do |channel_symbol|
        channel_symbol = channel_symbol.to_sym
        if subscriptions_hash[channel_symbol].nil?
          # Only if the client has not been subscribed already...

          channel = @channels[channel_symbol]
          if channel.nil? && options[:create_lazy]
            # If the channel is not existent yet and :create_lazy is true, create the channel...
            create(client_id, channel_symbol)
            channel = @channels[channel_symbol]
          end

          if !channel.nil?
            # Create a subscriber id for the client...
            channel_subscriber_id = channel.subscribe do |message_hash|
              # Here the actual relay to the receiver clients happens...
              if client_id != message_hash[:client_id] || options[:bounce]
                @qsif[:client_manager].web_socket(:client_id => client_id).relay(message_hash) # DO NOT MODIFY THIS LINE!
              end
            end
            # ... and add the channel information (channel symbol and subscriber id) to
            # the hash of channel subscriptions for the resp. client...
            subscriptions_hash[channel_symbol] = channel_subscriber_id
            (@channel_subscribers[channel_symbol] ||= []) << client_id
            channel_subscriber_ids << channel_subscriber_id

            notify(:type => :debug, :code => 2000, :receivers => @channels[channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s, :channel_subscriber_id => subscriptions_hash[channel_symbol]})
          else
            notify(:type => :error, :code => 2030, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s})
          end
        else
          notify(:type => :debug, :code => 2001, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s, :channel_subscriber_id => subscriptions_hash[channel_symbol]})
        end
      end

      return channel_subscriber_ids
    end

    #
    # Unsubscribes the client represented by client_id from the channels represented by
    # the channel_symbols array (instead of an array also a single channel symbol can
    # be passed). If :all is passed as channel symbol the client is unsubscribed from
    # all channels it is subscribed to.
    #
    # Returns the channel subscriber ids (array) of all channels which just have
    # been unsubscribed from.
    #
    def unsubscribe(client_id, channel_symbols, options = {})
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      channel_subscriber_ids = []
      subscriptions_hash = @channel_subscriptions[client_id] ||= {}

      if channel_symbols == [:all]
        channel_symbols = subscriptions_hash.keys
      end

      channel_symbols.each do |channel_symbol|
        channel_symbol = channel_symbol.to_sym
        if !subscriptions_hash[channel_symbol].nil?
          # Only if the client is subscribed...

          channel_subscriber_id = subscriptions_hash[channel_symbol]
          @channels[channel_symbol].unsubscribe(channel_subscriber_id)
          subscriptions_hash.delete(channel_symbol)
          @channel_subscribers[channel_symbol].delete(client_id)
          channel_subscriber_ids << channel_subscriber_id

          notify(:type => :debug, :code => 2020, :receivers => @channels[channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s, :channel_subscriber_id => channel_subscriber_id})
        else
          notify(:type => :debug, :code => 2021, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s})
        end
      end

      return channel_subscriber_ids
    end

    private

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end
end
