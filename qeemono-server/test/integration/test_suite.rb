require "test/unit"
require 'em-http-request'
require 'json'
require_relative '../../qeemono/server'

require 'mongoid'
require_relative 'server_response'


#
# Start the qeemono server first...
#
class QeeveeTestClient

  include EventMachine

  DEFAULT_SERVER_URL = "127.0.0.1:8080"


  def initialize(client_id = nil, url = nil)
    @url = url || DEFAULT_SERVER_URL
    @client_id = client_id
    connect_to_test_mongodb
    ServerResponse.delete_all
    raise "Mongo DB not empty!" unless ServerResponse.first.nil?
  end

  def self.stop_event_machine_after_sleep(duration)
    Thread.new do
      sleep(duration)
      EventMachine.stop
    end
  end

  def test_messages(messages = [], expected_responses_amount=0, duration=0.8)
    received_messages = []
    responses_counter = 0

    EventMachine.run do
      http = EventMachine::HttpRequest.new("ws://#{@url}").get(:timeout => 0, :query => {:client_id => @client_id})

      http.errback do
        raise "******* ERROR OCCURRED!!! Server started?"
      end

      http.callback do
        puts "\n\n----------"
        messages.each do |msg|
          http.send(msg)
          puts "s: #{msg}"
        end
        self.class.stop_event_machine_after_sleep(15) # Notaus!
      end

      http.stream do |msg|
        parsed_msg = JSON.parse(msg, :symbolize_names => true)
        received_messages << parsed_msg
        responses_counter += 1
        puts "r: #{parsed_msg}"
        if responses_counter >= expected_responses_amount
          EventMachine.stop
        end
      end
    end

    received_messages
  end # end - send_msg

  def connect_to_test_mongodb
    mongoid_conf = YAML::load_file('../../qeemono/config/mongoid_test.yml')
    Mongoid.configure do |config|
      config.master = Mongo::Connection.new(mongoid_conf['host'], mongoid_conf['port']).db(mongoid_conf['database'])
    end
  end
end

# ***

class BasicTest < Test::Unit::TestCase

  def test_no_client_id_given_and_bad_message
    messages = [
            "Hallo Mark!!!",
            "Bla Bla Bla"
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'warn',  :code => 7000, :param_keys => [:new_client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'warn',  :code => 7000, :param_keys => [:new_client_id, :wss]}}},
            {:params => {:arguments => {:type => 'fatal', :code => 9002, :param_keys => [:client_id, :message_hash, :err_msg]}}},
            {:params => {:arguments => {:type => 'warn',  :code => 7000, :param_keys => [:new_client_id, :wss]}}},
            {:params => {:arguments => {:type => 'fatal', :code => 9002, :param_keys => [:client_id, :message_hash, :err_msg]}}}
    ]
    actual_responses = QeeveeTestClient.new().test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_broadcast
    messages = [
            %q({"method":"send", "params":{"channels":["broadcast"], "message":{"method":"Katze", "params":"123"}}, "seq_id":569872820045801})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-1").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_send_to_self_and_broadcast
    messages = [
            %q({"method":"send", "params":{"client_ids":["test-client-981121"], "channels":["broadcastwb"], "message":{"method":"Katzensalat", "params":"12345"}}, "seq_id":56987820045801})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-981121").test_messages(messages, expected_responses.size+2)
    assert_server_notifications(expected_responses, actual_responses[0...-2])
    assert_equal({:method=>"Katzensalat", :params=>"12345", :client_id=>"test-client-981121", :version=>"1.0", :seq_id=>56987820045801}, actual_responses[-2])
    assert_equal({:method=>"Katzensalat", :params=>"12345", :client_id=>"test-client-981121", :version=>"1.0", :seq_id=>56987820045801}, actual_responses[-1])
  end

  def test_seq_id_coming_from_server_and_going_to_self
    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar"}, "seq_id":54629781}),
            %q({"method":"send", "params":{"client_ids":["test-client-87332451441"], "message":{"method":"Hund", "params":"878"}}, "seq_id":2352355788201}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5010, :param_keys => [:amount]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:method=>"hello", :params=>{:greeting => 'Hello Markimo! Your input is: "Foobar"'}, :client_id=>"test-client-87332451441", :version=>"1.0", :seq_id => 54629781},
            {:method=>"Hund", :params=>"878", :client_id=>"test-client-87332451441", :version=>"1.0", :seq_id=>2352355788201},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5020, :param_keys => [:amount, :message_handler_names]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5030, :param_keys => [:amount]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-87332451441").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_seq_id_via_broadcastwb
    messages = [
            %q({"method":"send", "params":{"channels":["broadcastwb"], "message":{"method":"Katze", "params":"123"}}, "seq_id":235845475201})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:method=>"Katze", :params=>"123", :client_id=>"test-client-98144121", :version=>"1.0", :seq_id=>235845475201}
    ]
    actual_responses = QeeveeTestClient.new("test-client-98144121").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  # TODO: should check that client is not subscribed => extend qeemono server accordingly...
  def test_send_to_existing_channel_without_being_subscribed
    messages = [
            %q({"method":"create_channels", "params":{"channels":["My Channel 4711"]}}),
            %q({"method":"send", "params":{"channels":["My Channel 4711"], "message":{"method":"Foobar", "params":"Hummel-7653"}}}),
            %q({"method":"destroy_channels", "params":{"channels":["My Channel 4711"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2040, :param_keys => [:client_id, :channel_symbol]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2050, :param_keys => [:client_id, :channel_symbol]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-94571").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_send_to_nonexisting_channel
    messages = [
            %q({"method":"send", "params":{"channels":["My Channel 4712"], "message":{"method":"Foobar", "params":"Hummel-7653"}}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'error', :code => 9515, :param_keys => [:handle_method_name, :message_handler_name, :message_handler_class, :version, :client_id, :message_hash, :err_msg]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-924571").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_subscribe_to_channel_without_having_created_it
    messages = [
            %q({"method":"subscribe_to_channels", "params":{"channels":["My Channel 4713"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'error', :code => 2030, :param_keys => [:client_id, :channel_symbol]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-94572").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_subscribe_to_channel_and_send_to_it_without_bounce
    messages = [
            %q({"method":"create_channels", "params":{"channels":["My Channel 4714"]}, "seq_id":1230001}),
            %q({"method":"subscribe_to_channels", "params":{"channels":["My Channel 4714"]}, "seq_id":1230002}),
            %q({"method":"send", "params":{"channels":["My Channel 4714"], "message":{"method":"Foobar", "params":"Hummel-765"}}, "seq_id":1230003}),
            %q({"method":"unsubscribe_from_channels", "params":{"channels":["My Channel 4714"]}, "seq_id":1230004}),
            %q({"method":"destroy_channels", "params":{"channels":["My Channel 4714"]}, "seq_id":1230005})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2040, :param_keys => [:client_id, :channel_symbol]}}, :seq_id => 1230001},
            {:params => {:arguments => {:type => 'debug', :code => 2020, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}, :seq_id => 1230004},
            {:params => {:arguments => {:type => 'debug', :code => 2050, :param_keys => [:client_id, :channel_symbol]}}, :seq_id => 1230005},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}, :seq_id => 1230002}
    ]
    actual_responses = QeeveeTestClient.new("test-client-94573").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_subscribe_to_channel_and_send_to_it_with_bounce
    messages = [
            %q({"method":"create_channels", "params":{"channels":["My Channel 4715"]}}),
            %q({"method":"subscribe_to_channels", "params":{"channels":["My Channel 4715"], "bounce":"true"}}),
            %q({"method":"no_operation", "params":{}}),
            %q({"method":"send", "params":{"channels":["My Channel 4715"], "message":{"method":"Foobar", "params":"Biene-72651"}}}),
            %q({"method":"unsubscribe_from_channels", "params":{"channels":["My Channel 4715"]}}),
            %q({"method":"destroy_channels", "params":{"channels":["My Channel 4715"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2040, :param_keys => [:client_id, :channel_symbol]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2020, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2050, :param_keys => [:client_id, :channel_symbol]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:method=>"Foobar", :params=>"Biene-72651", :client_id=>"test-client-8735", :version=>"1.0", :seq_id=>"none"}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8735").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_echo_without_being_registered_for_it
    messages = [
            %q({"method":"echo", "params":{"a":"123"}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'error', :code => 9500, :param_keys => [:method_name, :message_handler_names, :client_id, :version, :modules, :message_hash]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-873345").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_echo_with_being_registered_for_it
    messages = [
            %q({"method":"assign_to_modules", "params":{"modules":["__candidate_collection"]}}),
            %q({"method":"echo", "params":{"a":"123"}}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__candidate_collection"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:method=>"echo", :params=>{:a => "123"}, :client_id=>"test-client-811733245", :version=>"1.0", :seq_id=>"none"},
            {:method=>"echo2", :params=>{:a => "123"}, :client_id=>"test-client-811733245", :version=>"1.0", :seq_id=>"none"},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-811733245").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_echo_with_being_registered_for_it_and_addressing_concrete_message_handler
    messages = [
            %q({"method":"assign_to_modules", "params":{"modules":["__candidate_collection"]}}),
            %q({"method":"qeemono::cand.echo", "params":{"a":"123555"}}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__candidate_collection"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:method=>"echo", :params=>{:a => "123555"}, :client_id=>"test-client-872332451", :version=>"1.0", :seq_id=>"none"},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-872332451").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_echo_in_two_different_versions
    messages = [
            %q({"method":"assign_to_modules", "params":{"modules":["__candidate_collection"]}}),
            %q({"method":"echo", "params":{"a":"123"}}),
            %q({"method":"echo", "params":{"a":"456"}, "version":"1.4711"}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__candidate_collection"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:method=>"echo", :params=>{:a => "123"}, :client_id=>"test-client-8733245276", :version=>"1.0", :seq_id=>"none"},
            {:method=>"echo2", :params=>{:a => "123"}, :client_id=>"test-client-8733245276", :version=>"1.0", :seq_id=>"none"},
            {:method=>"echo", :params=>{:a => "456"}, :client_id=>"test-client-8733245276", :version=>"1.0", :seq_id=>"none"},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8733245276").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_register_unregister_message_handler_and_assign_unassign_module
    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar"}}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5010, :param_keys => [:amount]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:method=>"hello", :params=>{:greeting => 'Hello Markimo! Your input is: "Foobar"'}, :client_id=>"test-client-873783245144", :version=>"1.0", :seq_id=>"none"},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5020, :param_keys => [:amount, :message_handler_names]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5030, :param_keys => [:amount]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-873783245144").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_message_handler_with_method_that_fails_hard
    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.just_fail!", "params":{"input":"Foobar"}, "seq_id":54629721}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5010, :param_keys => [:amount]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'fatal', :code => 9510, :param_keys => [:handle_method_name, :message_handler_name, :message_handler_class, :version, :client_id, :message_hash, :err_msg]}}, :seq_id => 54629721},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5020, :param_keys => [:amount, :message_handler_names]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5030, :param_keys => [:amount]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-873324514431").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_message_handler_with_non_existing_method_although_listed_in_handled_methods_array
    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.this_method_does_not_exist", "params":{"input":"Foobar"}, "seq_id":5462129721}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5010, :param_keys => [:amount]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'fatal', :code => 9520, :param_keys => [:message_handler_name, :message_handler_class, :version, :method_name, :handle_method_name, :client_id, :message_hash]}}, :seq_id => 5462129721},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5020, :param_keys => [:amount, :message_handler_names]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5030, :param_keys => [:amount]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8733324514431").test_messages(messages, expected_responses.size)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_long_running_method
    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.i_need_long_time", "params":{"input":"Foobar"}, "seq_id":5412129721}),
            %q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})
    ]
    expected_responses = [
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}}},
            {:params => {:arguments => {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5010, :param_keys => [:amount]}}},
            {:params => {:arguments => {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'fatal', :code => 9530, :param_keys => [:handle_method_name, :message_handler_name, :message_handler_class, :version, :client_id, :message_hash, :thread_timeout]}}, :seq_id => 5412129721},
            {:params => {:arguments => {:type => 'debug', :code => 3020, :param_keys => [:client_id, :module_name]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5020, :param_keys => [:amount, :message_handler_names]}}},
            {:params => {:arguments => {:type => 'debug', :code => 5030, :param_keys => [:amount]}}}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8732324514431").test_messages(messages, expected_responses.size, 5)
    assert_server_notifications(expected_responses, actual_responses)
  end

#  def test_parallel_clients_processing
#    client_amount = 10
#    msg_count = 100
#
#    for client_no in (1..client_amount) do
#      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})], 2)
#      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})], 1)
#      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}})], 2)
#      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}})], 1)
#    end
#
#    actual_responses = {}
#    threads = []
#    for client_no in (1..client_amount) do
#      threads << Thread.new(client_no) do |tl_client_no|
#        messages=[]
#        for i in (1..msg_count) do
#          messages << %Q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar222-#{tl_client_no}-#{i}"}, "seq_id":4711000#{tl_client_no}000#{i}})
#        end
#        actual_responses[tl_client_no] = QeeveeTestClient.new("test-client-ppp-#{tl_client_no}").test_messages(messages, msg_count, 10)
#      end
#    end
#    threads.each { |t| t.join }
#    for client_no in (1..client_amount) do
#      for i in (msg_count..1) do
#        assert_equal({:method=>"hello", :params=>{:greeting => %Q(Hello Markimo! Your input is: "Foobar222-#{client_no}-#{i}")}, :client_id=>"test-client-ppp-#{client_no}", :version=>"1.0", :seq_id => "4711000#{client_no}000#{i}".to_i}, actual_responses[client_no][-i])
#      end
#    end
#
#    for client_no in (1..client_amount) do
#      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})], msg_count)
#    end
#  end

  def test_parallel_clients_processing_forked
    client_amount = 10
    msg_count = 100

    client_amount.times do |client_no|
      fork do
        # This block is executed in a sub process...
        messages = []
        messages << %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}})
        messages << %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}})
        for i in 1..msg_count do
          messages << %Q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar333-#{client_no}-#{i}"}, "seq_id":5711000#{client_no}000#{i}})
        end
        messages << %q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})
        responses = QeeveeTestClient.new("test-client-qppp-#{client_no}").test_messages(messages, msg_count)
        responses.each do |response|
          ServerResponse.create(
            client: "test-client-qppp-#{client_no}",
            seq_id: response[:seq_id].to_s,
            response_hash: response
          )
        end
      end # end - fork
    end

    Process.waitall

    client_amount.times do |client_no|
      for i in 1..msg_count do
        response_hash = JSON.parse(ServerResponse.where(client: "test-client-qppp-#{client_no}").and(seq_id: "5711000#{client_no}000#{i}").first.response_hash.to_json, :symbolize_names => true)
        assert_equal({:method=>"hello", :params=>{:greeting => %Q(Hello Markimo! Your input is: "Foobar333-#{client_no}-#{i}")}, :client_id=>"test-client-qppp-#{client_no}", :version=>"1.0", :seq_id => "5711000#{client_no}000#{i}".to_i}, response_hash)
      end
    end
  end

  # TODO: test (un-)subscribe to/from channels and create/destroy channels

  private

  def assert_server_notifications(expected_responses, actual_responses)
    assert_equal expected_responses.size, actual_responses.size, "The amount of expected_responses does not equal the amount of actual_responses"
    expected_responses.each_index do |index|
      assert_server_notification(expected_responses[index], actual_responses[index])
    end
  end

  def assert_server_notification(expected_response, actual_response, core_params = {})
    assert_not_nil expected_response, "expected_response may not be nil"
    assert_not_nil actual_response, "actual_response may not be nil"

    begin
      keys = expected_response[:params][:arguments].keys
      if keys.size == 3 && expected_response[:params].keys.size == 1 &&
              keys.include?(:type) && keys.include?(:code) && keys.include?(:param_keys) &&
              (expected_response.keys.size == 1 || (expected_response.keys.size == 2 && expected_response.has_key?(:seq_id)))
        short_version = true
      end
    rescue => e
      short_version = false
    end

    if short_version
      client_id = (expected_response[:client_id] || Qeemono::Notificator::SERVER_CLIENT_ID).to_s
      method = expected_response[:method] || 'notify'
      type = expected_response[:params][:arguments][:type].to_s
      code = expected_response[:params][:arguments][:code].to_i
      param_keys = expected_response[:params][:arguments][:param_keys]
      if expected_response[:seq_id]
        seq_id = expected_response[:seq_id].to_i
      else
        seq_id = Qeemono::Util::ThreadLocalPool::EMPTY_SEQ_ID.to_s
      end

      assert_equal client_id, actual_response[:client_id]
      assert_equal method, actual_response[:method]
      assert_equal type, actual_response[:params][:arguments][:type]
      assert_equal code, actual_response[:params][:arguments][:code]
      assert_equal param_keys, actual_response[:params][:arguments][:params].keys
      assert_equal seq_id, actual_response[:seq_id]
    else
      assert_equal(expected_response, actual_response)
    end
  end

end
