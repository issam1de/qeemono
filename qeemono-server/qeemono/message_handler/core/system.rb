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

        def handle_assign_to_modules(origin_client_id, params)
          modules = params[:modules]
          @qsif[:client_manager].assign_to_modules(origin_client_id, modules)
        end

        def handle_unassign_from_modules(origin_client_id, params)
          modules = params[:modules]
          @qsif[:client_manager].unassign_from_modules(origin_client_id, modules)
        end

        def handle_register_message_handler(origin_client_id, params)
          fq_file_names = params[:fq_file_names]
          fq_class_names = params[:fq_class_names]
          options = {}
          message_handlers = []

          fq_file_names.each do |fq_file_name|
            require fq_file_name

            if !fq_class_names.starts_with?(Qeemono::MessageHandler::Base::VENDOR_MESSAGE_HANDLER_PREFIX)
              raise "Vendor message handlers must start with #{Qeemono::MessageHandler::Base::VENDOR_MESSAGE_HANDLER_PREFIX}"
            end

            message_handler_object = instance_eval(fq_class_names).new
            message_handlers << message_handler_object
          end

          @qsif[:message_handler_manager].register(message_handlers, options)
        end

        def handle_unregister_message_handler(origin_client_id, params)
          raise "NOT IMPLEMENTED YET!"
        end

      end
    end
  end
end
