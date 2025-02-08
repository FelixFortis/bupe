defmodule Req.Behaviour do
  @callback get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
end
