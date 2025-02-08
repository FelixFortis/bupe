defmodule BUPE.HTTPClient do
  @moduledoc """
  Behaviour for HTTP clients used by BUPE.
  """
  @callback get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
end
