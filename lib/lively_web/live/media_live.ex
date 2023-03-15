defmodule LivelyWeb.MediaLive do
  use LivelyWeb, :live_view

  alias Lively.Media.Sample
  alias Lively.Media.Pipeline

  def mount(_session, _params, socket) do
    Phoenix.PubSub.subscribe(Lively.PubSub, "transcripts")

    socket =
      assign(socket, pipeline: nil, transcripts: [], levels: %{}, slide: 1, level_flip?: true)

    # DEV mode
    if connected?(socket) do
      socket =
        if System.get_env("DESIGN_MODE") == "true" do
          levels =
            Enum.reduce(0..1, %{}, fn i, acc ->
              ls = 1..100 |> Enum.map(fn _ -> -:rand.uniform(50) end)
              Map.put(acc, i, ls)
            end)

          assign(socket,
            pipeline: :fake,
            transcripts: [{0, 5000, "This is great"}, {5001, 10000, "So good."}],
            levels: levels
          )
        else
          {:noreply, socket} = play_pause("5", "mic", socket)
          # {:noreply, socket} = play_pause("5", "file", socket)
          socket
        end

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @keyboard "⌨️"
  @silence "😶"
  @simple_mappings %{
    # "[ Silence ]" => {:safe, @silence},
    # "[ typing ]" => {:safe, @keyboard},
    # "(keyboard clicking)" => {:safe, @keyboard},
    # "[BLANK_AUDIO]" => "..."
    "[ Silence ]" => nil,
    "[ typing ]" => nil,
    "(keyboard clicking)" => nil,
    "(clicking)" => nil,
    "[BLANK_AUDIO]" => nil
  }

  def handle_event("action", %{"buffer_duration" => d, "source" => s}, socket) do
    play_pause(d, s, socket)
  end

  def handle_info({:transcribed, text, part, start, stop}, socket) do
    socket = handle_command(text, socket)

    transcripts =
      if part == :final and text == "[BLANK_AUDIO]" do
        socket.assigns.transcripts
      else
        [{start, stop, text} | socket.assigns.transcripts]
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {a, b, t} ->
          rev =
            if is_binary(t) do
              t = String.trim(t)

              if t in Map.keys(@simple_mappings) do
                @simple_mappings[t]
              else
                if String.starts_with?(t, "[") and String.ends_with?(t, "]") do
                  {:safe,
                   t
                   |> String.replace("[", "<span class=\"text-purple-800\">")
                   |> String.replace("]", "</span>")}
                else
                  if String.starts_with?(t, "(") and String.ends_with?(t, ")") do
                    {:safe,
                     t
                     |> String.replace("(", "<span class=\"text-blue-800\">")
                     |> String.replace(")", "</span>")}
                  else
                    t
                  end
                end
              end
            else
              t
            end

          {a, b, rev}
        end)
      end

    {:noreply, assign(socket, transcripts: transcripts)}
  end

  def handle_info({:levels, amps}, socket) do
    current_index = Enum.count(socket.assigns.transcripts)
    first = hd(amps)
    amps = Map.get(socket.assigns.levels, current_index, [])
    socket = assign(socket, levels: Map.put(socket.assigns.levels, current_index, [first | amps]))

    {:noreply, socket}
  end

  def handle_info(notif, socket) do
    IO.inspect(notif, label: "received")
    {:noreply, socket}
  end

  def handle_command(text, socket) do
    lower = String.downcase(text)

    socket =
      if String.contains?(lower, "go to slide") do
        lower
        |> IO.inspect(label: "go to slide found")
        |> String.split("go to slide")
        |> IO.inspect(label: "split to get num")
        |> Enum.at(1)
        |> String.trim()
        |> IO.inspect(label: "remainder")
        |> to_num()
        |> IO.inspect(label: "parsed integer")
        |> case do
          :error -> socket
          {num, _} -> push_event(socket, "go-to-slide", %{slide: num})
        end
      else
        socket
      end

    socket =
      if String.contains?(lower, "slide forward") do
        push_event(socket, "next-slide", {})
      else
        socket
      end

    socket =
      if String.contains?(lower, "slide back") do
        push_event(socket, "previous-slide", {})
      else
        socket
      end

    socket
  end

  @num_names %{
    "one" => 1,
    "two" => 2,
    "three" => 3,
    "four" => 4,
    "five" => 5,
    "six" => 6,
    "seven" => 7,
    "eight" => 8,
    "nine" => 9
  }
  defp to_num(string) do
    string
    |> String.trim()
    |> then(fn s ->
      @num_names
      |> Enum.find(fn {name, _num} ->
        String.starts_with?(s, name)
      end)
      |> case do
        nil ->
          Integer.parse(s)

        {_, num} ->
          {num, ""}
      end
    end)
  end

  defp play_pause(d, s, socket) do
    if socket.assigns.pipeline do
      send(socket.assigns.pipeline, :stop)
      {:noreply, assign(socket, pipeline: nil)}
    else
      source =
        case s do
          "mic" -> :mic
          "file" -> {:file, Sample.get_path()}
        end

      IO.puts("starting")

      {:ok, pid} =
        Pipeline.start_link(
          source: source,
          to_pid: self(),
          buffer_duration: String.to_integer(d)
        )

      IO.puts("started")
      {:noreply, assign(socket, pipeline: pid, transcripts: [])}
    end
  end

  @height 600
  @width 1600
  @use_samples 300
  @floor -60
  defp levels_to_draw_commands(levels) do
    amount = Enum.count(levels)

    level =
      amount..0
      |> Enum.flat_map(fn index ->
        Map.get(levels, index, [])
      end)
      |> Enum.concat(for _ <- 1..@use_samples, do: @floor)
      |> Enum.take(@use_samples)
      |> Enum.reverse()

    samples = Enum.count(level)

    if samples > 0 do
      point = @width / samples * 2

      first =
        case level do
          [h | _] ->
            a = amp_to_one(h)
            "M0 #{r(a * @height)}"

          [] ->
            ""
        end

      cmds =
        level
        |> Enum.with_index()
        |> Enum.map(fn {amp, i} ->
          a = amp_to_one(amp)

          if rem(i, 50) == 0 do
            IO.inspect({amp, a, a * @height, r(a * @height), r(@height - a * @height)})
          end

          # IO.inspect({a, a * @height, @height - a * @height})
          "M#{r(point * i)} #{r(a * @height)}V#{r(@height - a * @height)}"
        end)
        |> Enum.join("")

      first <> cmds
    else
      ""
    end
  end

  defp levels_to_draw_commands_2(levels) do
    amount = Enum.count(levels)

    level =
      amount..0
      |> Enum.flat_map(fn index ->
        Map.get(levels, index, [])
      end)
      |> Enum.concat(for _ <- 1..@use_samples, do: 50)
      |> Enum.take(@use_samples)
      |> Enum.reverse()

    samples = Enum.count(level)

    if samples > 0 do
      point = @width / samples

      first =
        case level do
          [h | _] ->
            a = amp_to_one(h)
            "M0 #{r(a * @height)}"

          [] ->
            ""
        end

      cmds =
        level
        |> Enum.with_index()
        |> Enum.map(fn {amp, i} ->
          a = amp_to_one(amp)
          "L#{r(point * i)} #{r(a * @height)}"
        end)
        |> Enum.join("")

      first <> cmds
    else
      ""
    end
  end

  defp amp_to_one(amp) do
    positive = amp - @floor
    zero_to_one = positive / abs(@floor)
    min(max(zero_to_one, 0.0), 1.0)
  end

  defp r(float) do
    :erlang.float_to_binary(float, decimals: 2)
  end

  def render(assigns) do
    ~H"""
    <!-- Video as background -->
    <div class="absolute top-0 left-0 w-screen h-screen overflow-hidden">
      <video
        class="absolute top-0 left-0 w-screen h-screen object-cover"
        id="video-preview"
        phx-hook="video"
        autoplay
      >
      </video>
      <div class="reveal" style="width: 50vw;">
        <div class="slides">
          <section data-markdown>
            <textarea data-template>
    ## Lively Membranes


    ---

    ## Since the 90s

    - Self-taught developer, grew up doing web dev
    - Mixing technically interesting work with visually interesting work
    - Driven by realizing ideas, implementation, not theory
    - Are cool things naturally hard to do? Or are hard things simply cool?
    - Always new trouble in execution

    ---

    ## Why Elixir?

    - Great for dealing with inputs.
    - Simple ways of dealing with state.
    - Does not require a bunch of extra infrastructure
    - LiveView made it incredible for building expressive outputs.
    - Wiring inputs to outputs could not be easier.

    Images: Elixir logo, Erlang logo, Phoenix logo

    ---

    ## Inputs & Outputs

    - Projects I've done in recent years
    - Calendar eInk screen
    - Macro pad controlling lights
    - Stream Deck control software
    - Telegram bots
    - Inputs / Sources
    - APIs
    - Calendar URLs
    - Chat bots (Telegram/Slack)
    - Hardware controls
    - Webhooks
    - Outputs / Sinks
    - APIs
    - Web pages (LiveView)
    - Desktop apps (wx)
    - Hardware (lights, displays)
    - Chat bots (Telegram/Slack)

    ---

    ## Why Membrane?

    - Provides new Inputs and Outputs with audio and video
    - Traditionally difficult mediums to work with
    - Performs operations in Elixir, minimize shelling out
    - ffmpeg is rough to integrate with
    - Makes the results practical to use in Elixir
    - Make the actual process accessible in Elixir
    - More information than you might think

    Images: Membrane logo

    ---

    ## Transformations

    - Taking text from one place and putting it in another place is easy enough
    - Libraries like Image make manipulating pictures very powerful
    - Membrane enables transformations for audio and video.

    ---

    ## ML transforming unlikely formats

    - Not a big ML enthusiast but see some utility there
    - Allows transforming between messy formats
    - Text to image, weirdly through diffusion
    - Image to text, OCR quite well, object classification quite poorly
    - Audio to text, transcription
    - Text to audio, voice synthesis
    - Bumblebee makes this a tool box for builders like me

    ---

    ## Managing complexity

    - No extra infrastructure, all in a BEAM application
    - Media handling well abstracted
    - Machine learning well abstracted
    - Live web UI also well abstracted
    - Communication and coordination, thoroughly available
    - The most complicated code is the math to calculate duration from bitrate
    - Oh, and the SVG for the waveform was confusing

    ---

    ## What is this presentation doing?

    - Measure audio levels to produce a waveform using Membrane
    - Low-latency poor-quality, near-instant transcription
    - Slower better transcription using a longer section of speech
    - Interpreting transcript to of

    ---

    </textarea>
          </section>
        </div>
      </div>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 1600 900"
        stroke-width="6"
        stroke="currentColor"
        class="absolute top-0 left-0 stroke-white opacity-25"
        preserveAspectRatio="xMidYMin slice"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d={levels_to_draw_commands(@levels)} />
      </svg>
    </div>
    <!-- overlay covering full area -->
    <div class="absolute top-0 left-0 w-screen h-screen">
      <form phx-submit="action">
        <!--
        <label>
          Buffer duration, seconds<br />
          <input type="text" name="buffer_duration" value="5" />
        </label>
        <div class="my-4">
          <label><input type="radio" name="source" value="mic" checked /> Mic</label>
          <label><input type="radio" name="source" value="file" /> File</label>
        </div>
        <%= if @pipeline do %>
          <button class="bg-gray-600 p-2 rounded-md mt-4">Stop</button>
        <% else %>
          <button class="bg-green-600 p-2 rounded-md mt-4">Start</button>
        <% end %>
        -->
      </form>
    </div>
    <div class="absolute min-w-full min-h-[48px] bottom-0 right-0 text-right overflow-hidden flex flex-nowrap bg-black text-white opacity-70 justify-end">
      <span
        :for={{{start, stop, text}, index} <- @transcripts |> Enum.with_index() |> Enum.take(-50)}
        class="inline-block mr-1 whitespace-nowrap"
      >
        <%= if not is_nil(text) do %>
          <div class="flex text-xs text-gray-400 gap-4">
            <span class="mr-auto"><%= round(start / 1000) %></span>
          </div>
          <div>
            <%= text %>
          </div>
        <% end %>
      </span>
    </div>
    """
  end
end
