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
          [:assign_to_modules, :unassign_from_modules, :register_message_handler, :unregister_message_handler]
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
        #                      gets assigned to modules
        # * params:
        #   - :modules => array of modules the client is to be assigned to
        #
        def handle_assign_to_modules(origin_client_id, params)
          modules = params[:modules]
          @qsif[:client_manager].assign_to_modules(origin_client_id, modules)
        end

        #
        # Unassigns the given client id from modules.
        #
        # * origin_client_id - The originator (sender) of the message who
        #                      gets unassigned from modules
        # * params:
        #   - :modules => array of modules the client is to be unassigned from
        #
        def handle_unassign_from_modules(origin_client_id, params)
          modules = params[:modules]
          @qsif[:client_manager].unassign_from_modules(origin_client_id, modules)
        end

        #
        # Registers message handlers.
        #
        # * origin_client_id - The originator (sender) of the message
        # * params:
        #   - :filenames => array of full-qualified file names of
        #                   the message handlers to be registered
        #
        def handle_register_message_handler(origin_client_id, params)
          fq_filenames = params[:filenames]

          options = {}
          message_handlers = []

          fq_filenames.each do |fq_filename|
            require(fq_filename)
            fq_class_name = fq_class_name(fq_filename)
            message_handler_object = instance_eval(fq_class_name).new
            message_handlers << message_handler_object
          end

          @qsif[:message_handler_manager].register(message_handlers, options)
        end

        #
        # Registers message handlers.
        #
        # * origin_client_id - The originator (sender) of the message
        # * params:
        #   - :names => array of the message handler names to be
        #               unregistered
        #
        def handle_unregister_message_handler(origin_client_id, params)
          raise "NOT IMPLEMENTED YET!"
        end

        private

        def fq_class_name(fq_filename)
          file_fragments = fq_filename.split(Qeemono::MessageHandler::Base::VENDOR_MESSAGE_HANDLER_PATH_PREFIX)
          raise "Error in filename!" if file_fragments.size != 2
          filename = file_fragments[1]
          if filename.ends_with?('.rb')
            filename = filename[0..-4]
          else
            raise raise "Error in filename! '.rb' suffix is missing."
          end
          fq_class_name = Qeemono::MessageHandler::Base::VENDOR_MESSAGE_HANDLER_MODULE_PREFIX + StringUtils.classify(filename)
          return fq_class_name
        end
      end
    end
  end
end
