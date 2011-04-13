module Qeemono
  module MessageHandler
    module Core
      #
      # All system relevant message handlers.
      #
      class System < Qeemono::MessageHandler::Base

        def name
          :'qeemono::sys'
        end

        def description
          'system' # TODO: better description
        end

        def handled_methods
          [:assign_to_modules, :unassign_from_modules]
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
      end
    end
  end
end
