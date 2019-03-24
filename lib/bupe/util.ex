defmodule BUPE.Util do
  @moduledoc false

  @media_types File.read!(Path.expand("util/media-types.txt", __DIR__))

  @media_types
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    [extension, media] = line |> String.trim() |> String.split(",")

    def media_type("." <> unquote(extension)) do
      unquote(media)
    end
  end)

  def media_type(_), do: nil

  @spec media_type_from_path(Path.t()) :: nil | String.t()
  def media_type_from_path(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> media_type()
  end

  # Helper to generate an UUID, in particular version 4 as specified in
  # [RFC 4122](https://tools.ietf.org/html/rfc4122.html)
  @spec uuid4() :: String.t()
  def uuid4 do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    bin = <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    <<u0::32, u1::16, u2::16, u3::16, u4::48>> = bin

    Enum.map_join(
      [<<u0::32>>, <<u1::16>>, <<u2::16>>, <<u3::16>>, <<u4::48>>],
      <<45>>,
      &Base.encode16(&1, case: :lower)
    )
  end
end
