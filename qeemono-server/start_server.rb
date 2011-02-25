require './qeemono/server.rb'
require './qeemono/message_handler/core/system'
require './qeemono/message_handler/core/communication'

server = Qeemono::Server.new('127.0.0.1', '8080', {:debug => false})
mh_core = Qeemono::MessageHandler::Core::System.new
mh_communication = Qeemono::MessageHandler::Core::Communication.new
server.register_message_handlers([mh_core, mh_communication])
server.register_message_handlers(mh_core)
server.register_message_handlers(mh_communication)
server.register_message_handlers(Qeemono::MessageHandler::Core::Communication.new)
server.unregister_message_handlers([mh_core, mh_communication])
server.register_message_handlers([mh_core, mh_communication])

server.start
