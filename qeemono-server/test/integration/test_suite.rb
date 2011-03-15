require "test/unit"
require 'em-http-request'
require 'json'
require_relative '../../qeemono/server'


#
# Start the qeemono server first...
#
class QeeveeTestClient

  include EventMachine

  DEFAULT_SERVER_URL = "127.0.0.1:8080"


  def initialize(url = nil, client_id = nil)
    @url = url || DEFAULT_SERVER_URL
    @client_id = client_id
  end

  def self.stop_event_machine_after_sleep
    Thread.new do
      sleep(1)
      EventMachine.stop
    end
  end

  def test_messages(messages = [])
    received_message = []

    EventMachine.run do
      http = EventMachine::HttpRequest.new("ws://#{@url}").get(:timeout => 0, :query => {:client_id => @client_id})

      http.errback do
        puts "******* ERROR OCCURRED!!!"
      end

      http.callback do
        messages.each do |msg|
          http.send(msg)
          puts "s: #{msg}"
        end
        self.class.stop_event_machine_after_sleep
      end

      http.stream do |msg|
        parsed_msg = JSON.parse(msg, :symbolize_names => true)
        received_message << parsed_msg
        puts "r: #{parsed_msg}"
      end
    end

    received_message
  end # end - send_msg
end

# ***

class BasicTest < Test::Unit::TestCase

  def test_no_client_id_given
#    messages = []
    messages = ["Hallo Mark!!!", "TOK"]
    expected_responses = [
            {:type => 'warn',  :code => 7000, :param_keys => [:new_client_id, :wss]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'warn',  :code => 7000, :param_keys => [:new_client_id, :wss]},
            {:type => 'fatal', :code => 9002, :param_keys => [:client_id, :message_hash, :err_msg]},
            {:type => 'warn',  :code => 7000, :param_keys => [:new_client_id, :wss]},
            {:type => 'fatal', :code => 9002, :param_keys => [:client_id, :message_hash, :err_msg]}
    ]
    actual_responses = QeeveeTestClient.new().test_messages(messages)

    assert_server_notifications(expected_responses, actual_responses)
  end

  def assert_server_notifications(expected_responses, actual_responses)
    assert_equal expected_responses.size, actual_responses.size, "The amount of expected_responses does not equal the amount of actual_responses"
    expected_responses.each_index do |index|
      assert_server_notification(expected_responses[index], actual_responses[index])
    end
  end

  def assert_server_notification(expected_response, actual_response)
    assert_not_nil expected_response, "expected_response may not be nil"
    assert_not_nil actual_response, "actual_response may not be nil"

    type = expected_response[:type].to_s
    code = expected_response[:code].to_i
    param_keys = expected_response[:param_keys]

    assert_equal Qeemono::Notificator::SERVER_CLIENT_ID.to_s, actual_response[:client_id]
    assert_equal 'notify', actual_response[:method]
    assert_equal type, actual_response[:params][:arguments][:type]
    assert_equal code, actual_response[:params][:arguments][:code]
    assert_equal param_keys, actual_response[:params][:arguments][:params].keys
  end
end
