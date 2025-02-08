defmodule BUPETest do
  use BUPETest.Case, async: true
  import Mox
  doctest BUPE

  # Setup mocks
  setup :verify_on_exit!

  describe "parse/1" do
    test "parser should detect that file does not exist" do
      file_path = fixtures_dir("404.epub")
      msg = "file #{file_path} does not exist"

      assert_raise ArgumentError, msg, fn ->
        BUPE.parse(file_path)
      end
    end

    test "parser should detect invalid extensions" do
      file_path = fixtures_dir("30/bacon.xhtml")
      msg = "file #{file_path} does not have an '.epub' extension"

      assert_raise ArgumentError, msg, fn ->
        BUPE.parse(file_path)
      end
    end

    test "parser should report invalid EPUB mimetype" do
      msg = "invalid mimetype, must be 'application/epub+zip'"

      assert_raise RuntimeError, msg, fn ->
        "invalid_mimetype.epub" |> fixtures_dir() |> BUPE.parse()
      end
    end

    test "parser should return page content" do
      epub_path = "test/fixtures/hemingway-old-man-and-the-sea.epub"
      config = BUPE.parse(epub_path)
      page_4 = Enum.at(config.pages, 3)

      assert String.contains?(
               page_4.content,
               "He was an old man who fished alone in a skiff in the Gulf Stream"
             )
    end

    test "handles HTTP errors gracefully" do
      url = "http://localhost:9999/nonexistent.epub"

      expect(Req.Mock, :get, fn ^url, [raw: true] ->
        {:error, %{reason: :econnrefused}}
      end)

      assert_raise ArgumentError, "failed to fetch #{url}: %{reason: :econnrefused}", fn ->
        BUPE.Parser.run(url)
      end
    end

    test "can parse EPUB from URL" do
      url = "http://example.com/test.epub"
      epub_path = fixtures_dir("hemingway-old-man-and-the-sea.epub")
      epub_content = File.read!(epub_path)

      expect(Req.Mock, :get, fn ^url, [raw: true] ->
        {:ok, %{status: 200, body: epub_content}}
      end)

      config = BUPE.parse(url)
      assert config.title == "The Old Man and the Sea"
      assert config.creator == "Ernest Hemingway"
      assert is_list(config.pages)
    end
  end

  describe "build/3" do
    @tag :tmp_dir
    test "build epub document version 3", %{tmp_dir: tmp_dir} do
      config = config()

      output = Path.join(tmp_dir, "sample.epub")
      {:ok, {_name, epub}} = BUPE.build(config, output, [:memory])

      epub_info = BUPE.parse(epub)

      assert epub_info.title == config.title
      assert epub_info.creator == config.creator
      assert epub_info.version == config.version
    end

    test "builder should report invalid EPUB version" do
      config = config()
      config = Map.put(config, :version, "4.0")
      msg = "invalid EPUB version, expected '2.0' or '3.0'"

      assert_raise BUPE.InvalidVersion, msg, fn ->
        BUPE.build(config, "sample.epub")
      end
    end
  end
end
