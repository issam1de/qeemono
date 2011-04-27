require './qeemono/server.rb'

server = Qeemono::Server.new('127.0.0.1', '8080', {
        :ws_debug => false,
        :log_file_fq_path => 'log/qeemono_server.log',
        :enable_persistence => true
})

mh_system = Qeemono::MessageHandler::Core::System.new
mh_communication = Qeemono::MessageHandler::Core::Communication.new
mh_cc = Qeemono::MessageHandler::Core::CandidateCollection.new
mh_cc2 = Qeemono::MessageHandler::Core::CandidateCollection2.new
mh_persist = Qeemono::MessageHandler::Core::Persistence.new

#
# Note: Do not change the registration below because the tests rely on it!
#
server.message_handler_manager.register(nil, [mh_system, mh_communication])
server.message_handler_manager.register(nil, [mh_cc, mh_cc2])
server.message_handler_manager.register(nil, mh_system)
server.message_handler_manager.register(nil, mh_communication)
server.message_handler_manager.register(nil, Qeemono::MessageHandler::Core::Communication.new)
server.message_handler_manager.register(nil, Qeemono::MessageHandler::Core::CandidateCollection.new)
server.message_handler_manager.register(nil, Qeemono::MessageHandler::Core::CandidateCollection.new(:version => '1.4711'))
server.message_handler_manager.unregister(nil, [mh_system, mh_communication])
server.message_handler_manager.register(nil, [mh_system, mh_communication])
server.message_handler_manager.register(nil, mh_persist) if mh_persist

server.start
