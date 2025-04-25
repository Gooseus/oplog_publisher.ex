# Define encoders for external types
require Protocol

Protocol.derive(
  Jason.Encoder,
  BSON.ObjectId,
  only: []  # ObjectId has no fields we want to encode directly
)

defimpl Jason.Encoder, for: BSON.ObjectId do
  def encode(object_id, opts) do
    # Convert ObjectId to its string representation
    Jason.Encode.string(BSON.ObjectId.encode!(object_id), opts)
  end
end

Protocol.derive(
  Jason.Encoder,
  BSON.Timestamp,
  only: []  # ObjectId has no fields we want to encode directly
)

defimpl Jason.Encoder, for: BSON.Timestamp do
  def encode(timestamp, _opts) do
    # Convert Timestamp to an integer value
    Jason.Encode.integer(timestamp.value)
  end
end
