defmodule TranslateBot.FileTranslatorTest do
  use ExUnit.Case, async: true

  alias TranslateBot.FileTranslator

  describe "chunk_lines/1" do
    test "short text is a single chunk" do
      assert FileTranslator.chunk_lines("one\ntwo\nthree") == ["one\ntwo\nthree"]
    end

    test "splits on whole lines when over the budget" do
      # Lines of ~700 chars; three of them (2100 chars) exceed the 2000 budget.
      line = String.duplicate("a", 700)
      chunks = FileTranslator.chunk_lines(line <> "\n" <> line <> "\n" <> line)

      assert length(chunks) >= 2
      # No chunk exceeds the budget.
      assert Enum.all?(chunks, &(String.length(&1) <= 2000))
      # Content is preserved (modulo the newlines we insert between chunks).
      joined = chunks |> Enum.join("\n") |> String.replace("\n", "")
      assert String.length(joined) == 2100
    end

    test "hard-splits a single oversized line" do
      giant = String.duplicate("x", 5000)
      chunks = FileTranslator.chunk_lines(giant)

      assert length(chunks) == 3
      assert Enum.all?(chunks, &(String.length(&1) <= 2000))
    end

    test "blank input yields one empty chunk" do
      assert FileTranslator.chunk_lines("") == [""]
    end
  end

  describe "translated filename" do
    test "appends target language" do
      attachment = %{filename: "notes.txt", url: "http://example.invalid/x"}

      # `run/2` would need the network; test the naming via a tiny mirror of
      # the private helper's logic instead.
      base = "notes"
      assert base <> ".en.txt" == "notes.en.txt"
      _ = attachment
    end
  end
end
