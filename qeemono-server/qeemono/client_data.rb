#
# This data object may carry arbitrary client data.
# It is used by the persistence message handler for
# permanently storing client data.
#
class ClientData
  include Mongoid::Document

  field :owner_client_id, type: Symbol
  field :key, type: Symbol
  field :value, type: String
  field :public, type: Boolean
end
