ExUnit.start()

# Define mock for Req
Mox.defmock(Req.Mock, for: Req.Behaviour)
Application.put_env(:bupe, :req_client, Req.Mock)
