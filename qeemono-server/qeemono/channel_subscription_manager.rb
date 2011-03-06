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
    # Returns the channel subscriber ids (array) of all channels which just have
    # been subscribed to.
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
      subscriptions_hash = @qsif[:channel_subscriptions][client_id] ||= {}

      channel_symbols.each do |channel_symbol|
        channel_symbol = channel_symbol.to_sym
        if subscriptions_hash[channel_symbol].nil?
          # Only if the client has not been subscribed already...

          channel = (@qsif[:channels][channel_symbol] ||= EM::Channel.new) # If the channel is not existent yet, create it

          # Create a subscriber id for the client...
          channel_subscriber_id = channel.subscribe do |message|
            # Here the actual relay to the receiver clients happens...
            if client_id != message[:client_id] || options[:bounce]
              @qsif[:web_sockets][client_id].send message # DO NOT MODIFY THIS LINE!
            end
          end
          # ... and add the channel information (channel symbol and subscriber id) to
          # the hash of channel subscriptions for the resp. client...
          subscriptions_hash[channel_symbol] = channel_subscriber_id
          channel_subscriber_ids << channel_subscriber_id

          notify(:type => :debug, :code => 2000, :receivers => @qsif[:channels][channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s, :channel_subscriber_id => subscriptions_hash[channel_symbol]})
        else
          notify(:type => :debug, :code => 2001, :receivers => @qsif[:web_sockets][client_id], :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s, :channel_subscriber_id => subscriptions_hash[channel_symbol]})
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
      subscriptions_hash = @qsif[:channel_subscriptions][client_id] ||= {}

      if channel_symbols == [:all]
        channel_symbols = subscriptions_hash.keys
      end

      channel_symbols.each do |channel_symbol|
        channel_symbol = channel_symbol.to_sym
        if !subscriptions_hash[channel_symbol].nil?
          # Only if the client is subscribed...

          channel_subscriber_id = subscriptions_hash[channel_symbol]
          @qsif[:channels][channel_symbol].unsubscribe(channel_subscriber_id)
          subscriptions_hash.delete(channel_symbol)
          channel_subscriber_ids << channel_subscriber_id

          notify(:type => :debug, :code => 2020, :receivers => @qsif[:channels][channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s, :channel_subscriber_id => channel_subscriber_id})
        else
          notify(:type => :debug, :code => 2021, :receivers => @qsif[:web_sockets][client_id], :params => {:client_id => client_id, :channel_symbol => channel_symbol.to_s})
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
