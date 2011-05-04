module Qeemono
  module MessageHandler
    module Core
      #
      # This message handler defines system relevant methods.
      #
      class System < Qeemono::MessageHandler::Base

        def name
          :'qeemono::sys'
        end

        def description
          'system' # TODO: better description
        end

        def handled_methods
          [:assign_to_modules, :unassign_from_modules, :register_message_handlers, :unregister_message_handlers]
        end

        def modules
          [:core]
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

        #
        # Assigns the given client id to modules.
        #
        # * origin_client_id - The originator (sender) of the message who
        #                      gets assigned to modules.
        # * params:
        #   - :modules => Array of modules the client is to be assigned to.
        #
        def handle_assign_to_modules(origin_client_id, params)
          modules = params[:modules]
          @qsif[:client_manager].assign_to_modules(origin_client_id, modules)
        end

        #
        # Unassigns the given client id from modules.
        #
        # * origin_client_id - The originator (sender) of the message who
        #                      gets unassigned from modules.
        # * params:
        #   - :modules => Array of modules the client is to be unassigned from.
        #
        def handle_unassign_from_modules(origin_client_id, params)
          modules = params[:modules]
          @qsif[:client_manager].unassign_from_modules(origin_client_id, modules)
        end

        #
        # Registers message handlers.
        #
        # * origin_client_id - The originator (sender) of the message.
        # * params:
        #   - :filenames => Array of full-qualified file names of
        #                   the message handlers to be registered.
        #
        def handle_register_message_handlers(origin_client_id, params)
          fq_filenames = params[:filenames]

          options = {}
          message_handlers = []

          fq_filenames.each do |fq_filename|
            fq_class_name = fq_class_name(origin_client_id, fq_filename)
            if fq_class_name
              begin
                require(fq_filename)
                message_handler_object = instance_eval(fq_class_name).new
                message_handlers << message_handler_object
              rescue LoadError => e
                notify(:type => :error, :code => 5220, :receivers => @qsif[:client_manager].web_socket(:client_id => origin_client_id), :params => {:filename => fq_filename})
              end
            end
          end

          if !message_handlers.empty?
            @qsif[:message_handler_manager].register(origin_client_id, message_handlers, options)
          end
        end

        #
        # Registers message handlers.
        #
        # * origin_client_id - The originator (sender) of the message.
        # * params:
        #   - :fq_names => Array of full-qualified message handler
        #                  names (according to the fq_name method)
        #                  to be unregistered.
        #
        def handle_unregister_message_handlers(origin_client_id, params)
          fq_names = params[:fq_names]

          options = {}

          @qsif[:message_handler_manager].unregister(origin_client_id, fq_names, options)
        end

        private

        #
        # Returns the full-qualified class name of the given full-qualified
        # filename (fq_filename). In case of an error nil is returned and
        # the originator is informed about the error.
        #
        def fq_class_name(client_id, fq_filename)
          file_fragments = fq_filename.split(Qeemono::MessageHandler::Base::VENDOR_MESSAGE_HANDLER_PATH_PREFIX)
          if file_fragments.size != 2
            notify(:type => :error, :code => 5200, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:filename => fq_filename})
            return nil
          else
            filename = file_fragments[1]
            if filename.ends_with?('.rb')
              filename = filename[0..-4]
              fq_class_name = Qeemono::MessageHandler::Base::VENDOR_MESSAGE_HANDLER_MODULE_PREFIX + StringUtils.classify(filename)
              return fq_class_name
            else
              notify(:type => :error, :code => 5210, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:filename => fq_filename})
              return nil
            end
          end
        end

      end # end - class
    end
  end
end
