#
# For testing...
#
class ServerResponse
  include Mongoid::Document

  field :client, type: String
  field :seq_id, type: String
  field :response_hash, type: Hash
end
