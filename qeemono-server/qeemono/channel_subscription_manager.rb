module Qeemono
  class ChannelSubscriptionManager

    def initialize(server_interface)
      @qsif = server_interface
      @qsif[:channel_subscription_manager] = self
    end

    #
    # Subscribes the client represented by client_id to the channels represented by
    # the channel_symbols array (instead of an array also a single channel symbol
    # can be passed). Channels are created on-the-fly if not existent yet.
    #
    # Returns the channel subscriber ids (array) of all channels being subscribed to.
    #
    # options:
    #   * :bounce (bool) - If true, broadcasting messages to all subscribers of the given
    #                      channels (channel_symbols) includes the given client (client_id)
    #                      because it is also subscribed to the channels.
    #                      If false (the default), the client is not included (although subscribed)
    #
    def subscribe(client_id, channel_symbols, options = {})
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      channel_subscriber_ids = []

      channel_symbols.each do |channel_symbol|
        channel = (@qsif[:channels][channel_symbol] ||= EM::Channel.new)
        # Create a subscriber id for the client...
        channel_subscriber_id = channel.subscribe do |message|
          # Here the actual relay to the receiver clients happens...
          if client_id != message[:client_id] || options[:bounce]
            @qsif[:web_sockets][client_id].send message # DO NOT MODIFY THIS LINE!
          end
        end
        # ... and add the channel (a hash of the channel symbol and subscriber id) to
        # the hash of channel subscriptions for the resp. client...
        (@qsif[:channel_subscriptions][client_id] ||= {})[channel_symbol] = channel_subscriber_id
        channel_subscriber_ids << channel_subscriber_id

        notify(:type => :debug, :code => 2000, :receivers => @qsif[:channels][channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.inspect, :channel_subscriber_id => channel_subscriber_id}, :no_log => true)
      end

      notify(:type => :debug, :code => 2010, :params => {:client_id => client_id, :channel_symbols => channel_symbols.inspect, :channel_subscriber_ids => channel_subscriber_ids.inspect})

      return channel_subscriber_ids
    end

    #
    # Unsubscribes the client represented by client_id from the channels represented by
    # the channel_symbols array (instead of an array also a single channel symbol can
    # be passed). If :all is passed as channel symbol the client is unsubscribed from
    # all channels it is subscribed to.
    #
    # Returns the channel subscriber ids (array) of all channels being unsubscribed from.
    #
    def unsubscribe(client_id, channel_symbols, options = {})
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      channel_subscriber_ids = []

      if channel_symbols == [:all]
        channel_symbols = @qsif[:channel_subscriptions][client_id].keys
      end

      channel_symbols.each do |channel_symbol|
        channel_subscriber_id = @qsif[:channel_subscriptions][client_id][channel_symbol]
        @qsif[:channels][channel_symbol].unsubscribe(channel_subscriber_id)
        @qsif[:channel_subscriptions][client_id].delete(channel_symbol)
        channel_subscriber_ids << channel_subscriber_id

        notify(:type => :debug, :code => 2020, :receivers => @qsif[:channels][channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.inspect, :channel_subscriber_id => channel_subscriber_id}, :no_log => true)
      end

      notify(:type => :debug, :code => 2030, :params => {:client_id => client_id, :channel_symbols => channel_symbols.inspect, :channel_subscriber_ids => channel_subscriber_ids.inspect})

      return channel_subscriber_ids
    end

    private

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end
end
