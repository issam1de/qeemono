require './qeemono/server.rb'

server = Qeemono::Server.new('127.0.0.1', '8080', {:ws_debug => false})

mh_system = Qeemono::MessageHandler::Core::System.new
mh_communication = Qeemono::MessageHandler::Core::Communication.new
mh_cc = Qeemono::MessageHandler::Core::CandidateCollection.new

server.message_handler_manager.register([mh_system, mh_communication])
server.message_handler_manager.register(mh_cc)
server.message_handler_manager.register(mh_system)
server.message_handler_manager.register(mh_communication)
server.message_handler_manager.register(Qeemono::MessageHandler::Core::Communication.new)
server.message_handler_manager.unregister([mh_system, mh_communication])
server.message_handler_manager.register([mh_system, mh_communication])

server.start
