require "rspec"
require './qeemono/server.rb'

module Qeemono
  describe MessageHandlerManager do

    before(:each) do
      @mhm = Qeemono::MessageHandlerManager.new(nil, nil)
    end

    it "should register new handler" do
      @mhm.register(Qeemono::MessageHandler::Core::Communication.new)
    end
  end
end
