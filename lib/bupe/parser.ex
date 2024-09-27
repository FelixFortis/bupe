defmodule BUPE.Parser do
  @moduledoc ~S"""
  An [EPUB 3][EPUB] conforming parser. This implementation should support also
  EPUB 2.

  ## Example

      BUPE.Parser.parse("sample.epub")
      #=> %BUPE.Config{
        creator: "John Doe",
        nav: [
          %{idref: 'ode-to-bacon'},
          %{idref: 'ode-to-ham'},
          %{idref: 'ode-to-egg'}
        ],
        pages: [
          %{
            href: 'bacon.xhtml',
            id: 'ode-to-bacon',
            "media-type": 'application/xhtml+xml'
          },
          %{
            href: 'ham.xhtml',
            id: 'ode-to-ham',
            "media-type": 'application/xhtml+xml'
          },
          %{
            href: "egg.xhtml",
            id: 'ode-to-egg',
            "media-type": 'application/xhtml+xml'
          }
        ],
        styles: [
          %{href: 'stylesheet.css', id: 'styles', "media-type": 'text/css'}
        ],
        title: "Sample",
        unique_identifier: "EXAMPLE",
        version: "3.0"
      }

  [EPUB]: http://www.idpf.org/epub3/latest/overview

  """

  @doc """
  EPUB v3 parser
  """

  def run(<<0x04034B50::little-size(32), _::binary>> = epub), do: parse(epub)

  @spec run(Path.t()) :: BUPE.Config.t() | no_return
  def run(path) when is_binary(path) do
    path = path |> Path.expand() |> String.to_charlist()

    with :ok <- check_file(path),
         :ok <- check_extension(path) do
      parse(path)
    end
  end

  defp parse(epub) do
    with :ok <- check_mimetype(epub),
         {:ok, root_file} <- find_rootfile(epub),
         {:ok, xml} <- parse_xml_file(epub, root_file) do
      config =
        Enum.reduce(
          ~w(metadata manifest navigation extras)a,
          %BUPE.Config{title: nil, pages: nil},
          &parse_xml(&2, xml, &1)
        )

      %{config | pages: extract_page_content(epub, root_file, config.pages)}
    end
  end

  defp extract_page_content(epub, root_file, pages) do
    root_dir = Path.dirname(root_file)
    root_dir_length = String.length(root_dir) + 1

    page_paths = Enum.map(pages, &Path.join([root_dir, &1.href]))

    content =
      epub
      |> extract_files(page_paths)
      |> Map.new(fn {path, content} ->
        {Enum.drop(path, root_dir_length), content}
      end)

    Enum.map(pages, fn %{href: href} = page ->
      Map.put(page, :xhtml_content, Map.get(content, href, ""))
    end)
  end

  defp check_file(epub) do
    if File.exists?(epub) do
      :ok
    else
      raise ArgumentError, "file #{epub} does not exists"
    end
  end

  defp check_extension(epub) do
    if epub |> Path.extname() |> String.downcase() == ".epub" do
      :ok
    else
      raise ArgumentError, "file #{epub} does not have an '.epub' extension"
    end
  end

  defp check_mimetype(epub) do
    if epub |> extract_files(["mimetype"]) |> mimetype_valid?() do
      :ok
    else
      raise "invalid mimetype, must be 'application/epub+zip'"
    end
  end

  defp mimetype_valid?([{~c"mimetype", "application/epub+zip"}]), do: true
  defp mimetype_valid?(_), do: false

  defp find_rootfile(epub) do
    container = ~c"META-INF/container.xml"
    [{^container, content}] = extract_files(epub, [container])

    full_path =
      Regex.named_captures(~r/<rootfile\s.*full-path="(?<full_path>[^"]+)"\s/, content)[
        "full_path"
      ]

    if full_path do
      {:ok, full_path}
    else
      raise "could not find rootfile in #{container}"
    end
  end

  defp parse_xml_file(epub, file) do
    file = String.to_charlist(file)
    [{^file, content}] = extract_files(epub, [file])

    {xml, _rest} = content |> :erlang.bitstring_to_list() |> :xmerl_scan.string()

    {:ok, xml}
  end

  defp parse_xml(config, xml, :extras) do
    %{
      config
      | language: find_language(xml),
        version: find_xml(xml, filter: "/package/@version", type: :attribute),
        unique_identifier: find_xml(xml, filter: "/package/@unique-identifier", type: :attribute)
    }
  end

  defp parse_xml(config, xml, :manifest) do
    manifest =
      Map.new(
        [
          images: ["image/jpeg", "image/gif", "image/png", "image/svg+xml"],
          scripts: "application/javascript",
          styles: "text/css",
          pages: "application/xhtml+xml",
          audio: ["audio/mpeg", "audio/mp4"],
          fonts: [
            "application/font-sfnt",
            "application/font-woff",
            "font/woff2",
            "application/vnd.ms-opentype"
          ],
          toc: "application/x-dtbncx+xml"
        ],
        fn {key, pattern} ->
          {key, find_manifest(xml, pattern)}
        end
      )

    struct(config, manifest)
  end

  defp parse_xml(config, xml, :metadata) do
    metadata =
      Map.new(
        ~w(
          title
          identifier
          creator
          contributor
          date
          source
          type
          description
          format
          coverage
          publisher
          relation
          rights
          subject
      )a,
        fn key -> {key, find_metadata(xml, to_string(key))} end
      )

    config = struct(config, metadata)

    %{
      config
      | modified: find_metadata_property(xml, "dcterms:modified"),
        source: config.source || find_metadata_property(xml, "dcterms:source")
    }
  end

  defp parse_xml(config, xml, :navigation) do
    %{config | nav: find_xml(xml, filter: "/package/spine/*", type: :element)}
  end

  defp extract_files(archive, files) when is_list(files) do
    file_list = Enum.map(files, &if(is_binary(&1), do: String.to_charlist(&1), else: &1))

    case :zip.extract(archive, [{:file_list, file_list}, :memory]) do
      {:ok, content} ->
        content

      {:error, reason} ->
        raise reason
    end
  end

  defp find_metadata(xml, meta) do
    find_xml(xml, filter: "/package/metadata/dc:#{meta}/text()", type: :text)
  end

  defp find_metadata_property(xml, property) do
    find_xml(
      xml,
      filter: "/package/metadata/meta[contains(@property, '#{property}')]/text()",
      type: :text
    )
  end

  defp find_manifest(xml, media_types) when is_list(media_types) do
    filter = Enum.map_join(media_types, " or ", fn type -> "@media-type='#{type}'" end)

    find_xml(xml, filter: "/package/manifest/item[#{filter}]", type: :element)
  end

  defp find_manifest(xml, media_type), do: find_manifest(xml, [media_type])

  defp find_xml(xml, filter: filter, type: :attribute),
    do: filter |> xpath_string(xml) |> transform()

  defp find_xml(xml, filter: filter, type: type),
    do: filter |> xpath_string(xml) |> transform(from: type)

  defp find_language(xml) do
    find_metadata(xml, "language") || xpath_string("/package/@xml:lang", xml) |> transform()
  end

  defp xpath_string(xpath, xml) do
    xpath
    |> String.to_charlist()
    |> :xmerl_xpath.string(xml)
  end

  defp transform({
         :xmlElement,
         _name,
         _expanded_name,
         _nsinfo,
         _namespace,
         _parents,
         _pos,
         attributes,
         _content,
         _language,
         _xmlbase,
         :undeclared
       }) do
    Map.new(attributes, fn {:xmlAttribute, name, _, _, _, _, _, _, value, _} ->
      {name, value}
    end)
  end

  defp transform({:xmlText, _parents, _pos, _language, value, :text}), do: to_string(value)

  defp transform([
         {
           :xmlAttribute,
           _name,
           _expanded_name,
           _nsinfo,
           _namespace,
           _parents,
           _pos,
           _language,
           value,
           _normalized
         }
       ]),
       do: to_string(value)

  defp transform([], _), do: nil
  defp transform(source, from: :element), do: Enum.map(source, &transform/1)
  defp transform(source, from: :text), do: Enum.map_join(source, ", ", &transform/1)
end
