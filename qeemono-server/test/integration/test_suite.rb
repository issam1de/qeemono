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


  def initialize(client_id = nil, url = nil)
    @url = url || DEFAULT_SERVER_URL
    @client_id = client_id
  end

  def self.stop_event_machine_after_sleep(duration)
    Thread.new do
      sleep(duration)
      EventMachine.stop
    end
  end

  def test_messages(messages = [], duration=0.7)
    received_message = []

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
        self.class.stop_event_machine_after_sleep(duration)
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

  def test_no_client_id_given_and_bad_message
    messages = ["Hallo Mark!!!", "Bla Bla Bla"]
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

  def test_broadcast
    messages = [
            %q({"method":"send", "params":{"channels":["broadcast"], "message":{"method":"Katze", "params":"123"}}, "seq_id":56987820045801})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-1").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_send_to_self_and_broadcast
    messages = [
            %q({"method":"send", "params":{"client_ids":["test-client-981121"], "channels":["broadcastwb"], "message":{"method":"Katze", "params":"123"}}, "seq_id":56987820045801})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-981121").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-2])
    assert_equal({:method=>"Katze", :params=>"123", :client_id=>"test-client-981121", :version=>"1.0", :seq_id=>56987820045801}, actual_responses[-2])
    assert_equal({:method=>"Katze", :params=>"123", :client_id=>"test-client-981121", :version=>"1.0", :seq_id=>56987820045801}, actual_responses[-1])
  end

  def test_seq_id_coming_from_server_and_going_to_self
    QeeveeTestClient.new("test-client-87332451441").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
    QeeveeTestClient.new("test-client-87332451441").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})])

    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar"}, "seq_id":54629781}),
            %q({"method":"send", "params":{"client_ids":["test-client-87332451441"], "message":{"method":"Hund", "params":"878"}}, "seq_id":2352355788201})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]},
            {:type => 'debug', :code => 5010, :param_keys => [:amount]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-87332451441").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-2])
    assert_equal({:method=>"hello", :params=>{:greeting => 'Hello Mark! Your input is: "Foobar"'}, :client_id=>"test-client-87332451441", :version=>"1.0", :seq_id => 54629781}, actual_responses[-2])
    assert_equal({:method=>"Hund", :params=>"878", :client_id=>"test-client-87332451441", :version=>"1.0", :seq_id=>2352355788201}, actual_responses[-1])
  end

  def test_seq_id_via_broadcastwb
    messages = [
            %q({"method":"send", "params":{"channels":["broadcastwb"], "message":{"method":"Katze", "params":"123"}}, "seq_id":235845475201})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-98144121").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-1])
    assert_equal({:method=>"Katze", :params=>"123", :client_id=>"test-client-98144121", :version=>"1.0", :seq_id=>235845475201}, actual_responses[-1])
  end

  def test_send_to_channel_without_being_subscribed
    QeeveeTestClient.new("test-client-94572").test_messages([%q({"method":"destroy_channels", "params":{"channels":["My Channel 4711"]}})])

    messages = [
            %q({"method":"send", "params":{"channels":["My Channel 4711"], "message":{"method":"Foobar", "params":"Hummel-7653"}}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'error', :code => 9515, :param_keys => [:handle_method_name, :message_handler_name, :message_handler_class, :version, :client_id, :message_hash, :err_msg]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-94572").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_subscribe_to_channel_without_having_created_it
    QeeveeTestClient.new("test-client-94572").test_messages([%q({"method":"destroy_channels", "params":{"channels":["My Channel 4711"]}})])

    messages = [
            %q({"method":"subscribe_to_channels", "params":{"channels":["My Channel 4711"]}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'error', :code => 2030, :param_keys => [:client_id, :channel_symbol]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-94572").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_subscribe_to_channel_and_send_to_it_without_bounce
    QeeveeTestClient.new("test-client-8733245").test_messages([%q({"method":"destroy_channels", "params":{"channels":["My Channel 4711"]}})])

    messages = [
            %q({"method":"create_channels", "params":{"channels":["My Channel 4711"]}}),
            %q({"method":"subscribe_to_channels", "params":{"channels":["My Channel 4711"]}}),
            %q({"method":"send", "params":{"channels":["My Channel 4711"], "message":{"method":"Foobar", "params":"Hummel-765"}}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 2040, :param_keys => [:client_id, :channel_symbol]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-94572").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_subscribe_to_channel_and_send_to_it_with_bounce
    QeeveeTestClient.new("test-client-8733245").test_messages([%q({"method":"unsubscribe_from_channels", "params":{"channels":["My Channel 4711"]}}),])
    QeeveeTestClient.new("test-client-8733245").test_messages([%q({"method":"destroy_channels", "params":{"channels":["My Channel 4711"]}})])

    messages = [
            %q({"method":"create_channels", "params":{"channels":["My Channel 4711"]}}),
            %q({"method":"subscribe_to_channels", "params":{"channels":["My Channel 4711"], "bounce":"true"}}),
            %q({"method":"send", "params":{"channels":["My Channel 4711"], "message":{"method":"Foobar", "params":"Hummel-7651"}}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 2040, :param_keys => [:client_id, :channel_symbol]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8735").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-1])
    assert_equal({:method=>"Foobar", :params=>"Hummel-7651", :client_id=>"test-client-8735", :version=>"1.0", :seq_id=>"none"}, actual_responses[-1])
  end

  def test_echo_without_being_registered_for_it
    QeeveeTestClient.new("test-client-8733245").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__candidate_collection"]}})])

    messages = [
            %q({"method":"echo", "params":{"a":"123"}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'error', :code => 9500, :param_keys => [:method_name, :message_handler_names, :client_id, :version, :modules, :message_hash]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-873345").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_echo_with_being_registered_for_it
    QeeveeTestClient.new("test-client-8733245").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__candidate_collection"]}})])

    messages = [
            %q({"method":"assign_to_modules", "params":{"modules":["__candidate_collection"]}}),
            %q({"method":"echo", "params":{"a":"123"}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8733245").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-2])
    assert_equal({:method=>"echo", :params=>{:a => "123"}, :client_id=>"test-client-8733245", :version=>"1.0", :seq_id=>"none"}, actual_responses[-2])
    assert_equal({:method=>"echo2", :params=>{:a => "123"}, :client_id=>"test-client-8733245", :version=>"1.0", :seq_id=>"none"}, actual_responses[-1])
  end

  def test_echo_with_being_registered_for_it_and_addressing_concrete_message_handler
    QeeveeTestClient.new("test-client-87332451").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__candidate_collection"]}})])

    messages = [
            %q({"method":"assign_to_modules", "params":{"modules":["__candidate_collection"]}}),
            %q({"method":"qeemono::cand.echo", "params":{"a":"123"}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-87332451").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-1])
    assert_equal({:method=>"echo", :params=>{:a => "123"}, :client_id=>"test-client-87332451", :version=>"1.0", :seq_id=>"none"}, actual_responses[-1])
  end

  def test_echo_in_two_different_versions
    QeeveeTestClient.new("test-client-8733245276").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__candidate_collection"]}})])

    messages = [
            %q({"method":"assign_to_modules", "params":{"modules":["__candidate_collection"]}}),
            %q({"method":"echo", "params":{"a":"123"}}),
            %q({"method":"echo", "params":{"a":"456"}, "version":"1.4711"})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8733245276").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-3])
    assert_equal({:method=>"echo", :params=>{:a => "123"}, :client_id=>"test-client-8733245276", :version=>"1.0", :seq_id=>"none"}, actual_responses[-3])
    assert_equal({:method=>"echo2", :params=>{:a => "123"}, :client_id=>"test-client-8733245276", :version=>"1.0", :seq_id=>"none"}, actual_responses[-2])
    assert_equal({:method=>"echo", :params=>{:a => "456"}, :client_id=>"test-client-8733245276", :version=>"1.0", :seq_id=>"none"}, actual_responses[-1])
  end

  def test_register_message_handler
    QeeveeTestClient.new("test-client-8733245144").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
    QeeveeTestClient.new("test-client-8733245144").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})])

    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar"}})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]},
            {:type => 'debug', :code => 5010, :param_keys => [:amount]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8733245144").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses[0...-1])
    assert_equal({:method=>"hello", :params=>{:greeting => 'Hello Mark! Your input is: "Foobar"'}, :client_id=>"test-client-8733245144", :version=>"1.0", :seq_id=>"none"}, actual_responses[-1])
  end

  def test_message_handler_with_method_that_fails_hard
    QeeveeTestClient.new("test-client-873324514431").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
    QeeveeTestClient.new("test-client-873324514431").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})])

    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.just_fail!", "params":{"input":"Foobar"}, "seq_id":54629721})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]},
            {:type => 'debug', :code => 5010, :param_keys => [:amount]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]},
            {:type => 'fatal', :code => 9510, :param_keys => [:handle_method_name, :message_handler_name, :message_handler_class, :version, :client_id, :message_hash, :err_msg]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-873324514431").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_message_handler_with_non_existing_method_although_listed_in_handled_methods_array
    QeeveeTestClient.new("test-client-8733324514431").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
    QeeveeTestClient.new("test-client-8733324514431").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})])

    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.this_method_does_not_exist", "params":{"input":"Foobar"}, "seq_id":5462129721})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]},
            {:type => 'debug', :code => 5010, :param_keys => [:amount]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]},
            {:type => 'fatal', :code => 9520, :param_keys => [:message_handler_name, :message_handler_class, :version, :method_name, :handle_method_name, :client_id, :message_hash]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8733324514431").test_messages(messages)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_long_running_method
    QeeveeTestClient.new("test-client-8732324514431").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
    QeeveeTestClient.new("test-client-8732324514431").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})])

    messages = [
            %q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}}),
            %q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}}),
            %q({"method":"mark::test_mh.i_need_long_time", "params":{"input":"Foobar"}, "seq_id":5412129721})
    ]
    expected_responses = [
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 2000, :param_keys => [:client_id, :channel_symbol, :channel_subscriber_id]},
            {:type => 'debug', :code => 6000, :param_keys => [:client_id, :wss]},
            {:type => 'debug', :code => 5000, :param_keys => [:message_handler_name, :handled_methods, :modules, :message_handler_class, :version]},
            {:type => 'debug', :code => 5010, :param_keys => [:amount]},
            {:type => 'debug', :code => 3000, :param_keys => [:client_id, :module_name]},
            {:type => 'fatal', :code => 9530, :param_keys => [:handle_method_name, :message_handler_name, :message_handler_class, :version, :client_id, :message_hash, :thread_timeout]}
    ]
    actual_responses = QeeveeTestClient.new("test-client-8732324514431").test_messages(messages, 5)
    assert_server_notifications(expected_responses, actual_responses)
  end

  def test_parallel_clients_processing
    client_amount = 10
    msg_count = 500

    for client_no in (1..client_amount) do
      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})])
      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}})])
      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}})])
    end

    actual_responses = {}
    threads = []
    for client_no in (1..client_amount) do
      threads << Thread.new(client_no) do |tl_client_no|
        messages=[]
        for i in (1..msg_count) do
          messages << %Q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar222-#{tl_client_no}-#{i}"}, "seq_id":4711000#{tl_client_no}000#{i}})
        end
        actual_responses[tl_client_no] = QeeveeTestClient.new("test-client-ppp-#{tl_client_no}").test_messages(messages, 10)
      end
    end
    threads.each { |t| t.join }
    for client_no in (1..client_amount) do
      for i in (msg_count..1) do
        assert_equal({:method=>"hello", :params=>{:greeting => %Q(Hello Mark! Your input is: "Foobar222-#{client_no}-#{i}")}, :client_id=>"test-client-ppp-#{client_no}", :version=>"1.0", :seq_id => "4711000#{client_no}000#{i}".to_i}, actual_responses[client_no][-i])
      end
    end

    for client_no in (1..client_amount) do
      QeeveeTestClient.new("test-client-ppp-#{client_no}").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
    end
  end

  def test_parallel_clients_processing_forked
    client_amount = 10
    msg_count = 500

    client_amount.times do |client_no|
      fork do

        QeeveeTestClient.new("test-client-qppp-#{client_no}").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])
        QeeveeTestClient.new("test-client-qppp-#{client_no}").test_messages([%q({"method":"unassign_from_modules", "params":{"modules":["__marks_module"]}})])
        QeeveeTestClient.new("test-client-qppp-#{client_no}").test_messages([%q({"method":"register_message_handlers", "params":{"filenames":["/Users/schmatz/projects/qeevee/qeemono/qeemono-server/qeemono/message_handler/vendor/org/tztz/marks_test_message_handler.rb"]}})])
        QeeveeTestClient.new("test-client-qppp-#{client_no}").test_messages([%q({"method":"assign_to_modules", "params":{"modules":["__marks_module"]}})])

        # This block is executed in a sub process...
        messages = []
        responses = []
        for i in 1..msg_count do
          messages << %Q({"method":"mark::test_mh.say_hello", "params":{"input":"Foobar333-#{client_no}-#{i}"}, "seq_id":5711000#{client_no}000#{i}})
        end
        responses = QeeveeTestClient.new("test-client-qppp-#{client_no}").test_messages(messages, 10)
        for i in msg_count..1 do
          assert_equal({:method=>"hello", :params=>{:greeting => %Q(Hello Mark! Your input is: "Foobar333-#{client_no}-#{i}")}, :client_id=>"test-client-qppp-#{client_no}", :version=>"1.0", :seq_id => "5711000#{client_no}000#{i}".to_i}, responses[-i])
        end

        QeeveeTestClient.new("test-client-qppp-#{client_no}").test_messages([%q({"method":"unregister_message_handlers", "params":{"fq_names":["__marks_module#mark::test_mh"]}})])

      end # end - fork
    end

    Process.waitall
  end

  # TODO: test (un-)subscribe to/from channels and create/destroy channels

  private

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
