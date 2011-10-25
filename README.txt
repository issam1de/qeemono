#
# This is the qeemono server.
# A lightweight, Web Socket and EventMachine based server.
#
# (c) 2011, Mark von Zeschau
#
#
# Core features:
# --------------
#
#   - lightweight
#   - modular
#   - event-driven
#   - bi-directional push (Web Socket)
#   - stateful
#   - session aware
#   - resistant against session hijacking
#   - thin JSON protocol
#   - automatic protocol validation
#   - no thick framework underlying
#   - communication can be 1-to-1, 1-to-many, 1-to-channel(s), 1-to-broadcast, and 1-to-server
#       (broadcast and channel communication is possible with 'bounce' flag)
#   - message handlers use observer pattern to register
#   - starvation-save (message handlers which run infinitely)
#   - message acknowledgement
#
# Requirements on server-side:
# ----------------------------
#
#   Needed Ruby Gems:
#     - eventmachine (https://rubygems.org/gems/eventmachine)
#     - em-websocket (https://rubygems.org/gems/em-websocket) [depends on eventmachine]
#     - iconv (https://rubygems.org/gems/iconv - see also http://rvm.beginrescueend.com/packages/iconv)
#     - json (https://rubygems.org/gems/json [depends on iconv]
#     - log4r (https://rubygems.org/gems/log4r)
#     - mongoid (https://rubygems.org/gems/mongoid)
#     - bson_ext (https://rubygems.org/gems/bson_ext) - to make mongoid faster
#     - [needed for testing] em-http-request (https://rubygems.org/gems/em-http-request)
#
#   To install them all just execute the following in a terminal window:
#   gem install <gem-name> <gem-name> <etc.>
#
# Requirements on client-side:
# ----------------------------
#
#    - jQuery (http://jquery.com)
#    - Web Socket support - built-in in most modern browsers. If not built-in, you can
#                           utilize e.g. the HTML5 Web Socket implementation powered
#                           by Flash (see https://github.com/gimite/web-socket-js).
#                           All you need is to load the following JavaScript files in
#                           your HTML page:
#                             - swfobject.js
#                             - FABridge.js
#                             - web_socket.js
#
# External documentation:
# -----------------------
#
#   - Web Sockets (http://www.w3.org/TR/websockets/)
#   - EventMachine (http://rubyeventmachine.com/)
#
#
#
# [ The qeemono server and all its dependencies are tested under Ruby 1.9.x ]
#
