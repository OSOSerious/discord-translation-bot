defmodule TranslateBotTest do
  use ExUnit.Case, async: true

  alias TranslateBot.{Cache, Channels, Detect, Translation}

  # `mix test --no-start` keeps Nostrum offline, so start our own GenServers
  # (Cache / Channels own the ETS tables) before each test module runs.
  setup_all do
    {:ok, _} = Cache.start_link()
    {:ok, _} = Channels.start_link()
    :ok
  end

  # -- Detect ---------------------------------------------------------------

  describe "Detect.detect/1" do
    test "Spanish accents decide immediately" do
      assert Detect.detect("¿Cómo estás?") == "es"
      assert Detect.detect("mañana será un gran día") == "es"
    end

    test "English stop words win when no accents" do
      assert Detect.detect("the quick brown fox is over there") == "en"
      assert Detect.detect("I think that this is the one") == "en"
    end

    test "Spanish stop words win when no accents" do
      assert Detect.detect("la casa de mi madre es muy grande") == "es"
    end

    test "defaults to English with no signal" do
      assert Detect.detect("xyzzy") == "en"
    end
  end

  describe "Detect.other/1" do
    test "swaps languages" do
      assert Detect.other("es") == "en"
      assert Detect.other("en") == "es"
    end
  end

  # -- Translation (uses fake backends from test config) --------------------

  describe "Translation.auto/1" do
    test "translates via the fallback chain" do
      assert {:ok, result} = Translation.auto("hello there")
      # FailingBackend errors first, UpperBackend wins:
      assert result.text == "HELLO THERE"
      assert result.origin == :fresh
      assert result.from == "en"
      assert result.to == "es"
    end

    test "second call is served from cache" do
      {:ok, first} = Translation.auto("cache me")
      {:ok, second} = Translation.auto("cache me")
      assert first.origin == :fresh
      assert second.origin == :cached
    end

    test "empty text errors" do
      assert {:error, :empty_text} = Translation.auto("   ")
    end

    test "spanish input flips direction" do
      assert {:ok, %{from: "es", to: "en"}} = Translation.auto("¿dónde está la biblioteca?")
    end
  end

  describe "Translation.translate/3" do
    test "same source and target is an error" do
      assert {:error, :same_language} = Translation.translate("hi", "en", "en")
    end

    test "forced direction works via fallback chain" do
      assert {:ok, text, :fresh} = Translation.translate("force me", "en", "es")
      assert text == "FORCE ME"
    end
  end

  # -- Cache ---------------------------------------------------------------

  describe "Cache" do
    test "miss then hit" do
      Cache.clear()
      assert :miss = Cache.fetch("greeting", "en", "es")
      :ok = Cache.put("greeting", "en", "es", "saludo")
      assert {:ok, "saludo"} = Cache.fetch("greeting", "en", "es")
    end

    test "direction matters" do
      Cache.clear()
      :ok = Cache.put("one way", "en", "es", "un camino")
      assert :miss = Cache.fetch("one way", "es", "en")
    end
  end

  # -- Channels ------------------------------------------------------------

  describe "Channels.toggle/1" do
    test "flips state per channel" do
      channel_id = 99_999_999

      first = Channels.toggle(channel_id)
      assert first == true
      assert Channels.enabled?(channel_id)

      second = Channels.toggle(channel_id)
      assert second == false
      refute Channels.enabled?(channel_id)
    end
  end

  # -- Commands ------------------------------------------------------------

  describe "TranslateBot.Commands" do
    test "defines translate, translate-to, detect and auto" do
      names = TranslateBot.Commands.all() |> Enum.map(& &1.name)
      assert names == ["translate", "translate-to", "detect", "auto"]
    end

    test "translate-to offers es/en choices" do
      cmd = Enum.find(TranslateBot.Commands.all(), &(&1.name == "translate-to"))
      lang_opt = Enum.find(cmd.options, &(&1.name == "lang"))
      choices = lang_opt.choices |> Enum.map(& &1.value)
      assert choices == ["es", "en"]
    end
  end
end
