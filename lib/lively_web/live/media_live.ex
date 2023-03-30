defmodule LivelyWeb.MediaLive do
  use LivelyWeb, :live_view

  alias Lively.Media.Sample
  alias Lively.Media.Pipeline

  @impl true
  def mount(_session, _params, socket) do
    Phoenix.PubSub.subscribe(Lively.PubSub, "transcripts")

    socket =
      assign(socket,
        pipeline: nil,
        transcripts: [],
        instants: [],
        levels: %{},
        slide: 1,
        time: time(),
        level_flip?: true
      )

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
            instants: ["Love it.", "Lovely."],
            levels: levels
          )
        else
          # {:noreply, socket} = play_pause("5", "mic", socket)
          # {:noreply, socket} = play_pause("5", "file", socket)
          socket
        end

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  defp time, do: :erlang.system_time(:millisecond)

  #  @keyboard "⌨️"
  #  @silence "😶"
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

  @impl true
  def handle_event("action", %{"buffer_duration" => d, "source" => s}, socket) do
    play_pause(d, s, socket)
  end

  @impl true
  def handle_event("run", _, socket) do
    play_pause("5", "mic", socket)
  end

  @impl true
  def handle_event(other, params, socket) do
    IO.inspect({other, params}, label: "event")
    {:noreply, socket}
  end

  @impl true
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

    {:noreply, assign(socket, transcripts: transcripts, instants: [])}
  end

  def handle_info({:instant, text, part, _start, _stop}, socket) do
    socket =
      if part == :final and text == "[BLANK_AUDIO]" do
        socket
      else
        t = text

        text =
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

        instants = [text | socket.assigns.instants]
        assign(socket, instants: instants)
      end

    {:noreply, socket}
  end

  def handle_info({:levels, amps}, socket) do
    current_index = Enum.count(socket.assigns.transcripts)
    first = hd(amps)
    amps = Map.get(socket.assigns.levels, current_index, [])
    # IO.inspect(Enum.count(amps), label: "levels for #{current_index}")
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
      if String.contains?(lower, "slide forward") or String.contains?(lower, "next slide") or
           String.contains?(lower, "onward") do
        push_event(socket, "next-slide", %{})
      else
        socket
      end

    socket =
      if String.contains?(lower, "slide back") or String.contains?(lower, "previous slide") do
        push_event(socket, "previous-slide", %{})
      else
        socket
      end

    socket =
      if String.contains?(lower, "clear screen") do
        assign(socket, transcripts: [], instants: [], levels: %{})
      else
        socket
      end

    socket =
      if String.contains?(lower, "full reset") do
        socket
        |> push_event("go-to-slide", %{slide: 0})
        |> assign(transcripts: [], instants: [], levels: %{})
      else
        socket
      end

    socket
  end

  @num_names %{
    "zero" => 0,
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
  @use_samples 150
  # @use_samples 100
  @floor -60
  @padding 150
  defp levels_to_draw_commands(levels) do
    amount = Enum.count(levels)

    level =
      amount..0
      |> Enum.flat_map(fn index ->
        Map.get(levels, index, [])
      end)
      # |> Enum.concat(for _ <- 1..@use_samples, do: @floor)
      |> Enum.take(@use_samples)
      |> Enum.reverse()

    samples = Enum.count(level)

    if samples > 0 do
      point = @width / 2 / @use_samples

      cmds =
        level
        |> Enum.with_index()
        |> Enum.map(fn {amp, i} ->
          a =
            case amp do
              :clip -> 1.0
              :infinity -> 1.0
              num when is_number(num) -> amp_to_one(amp)
              _ -> 0.0
            end

          top_y = @padding + @height / 2 - @height / 2 * a
          size = @height * a

          # IO.inspect({a, a * @height, @height - a * @height})
          "M#{r(point * i * 2)} #{r(top_y)}v#{r(size)}"
        end)
        |> Enum.join("")

      # |> IO.inspect()

      # IO.puts("")

      cmds
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
      |> Enum.concat(for _ <- 1..@use_samples, do: @floor)
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
          # IO.inspect(a * @height)
          "L#{r(point * i)} #{r(@height - a * @height)}"
        end)
        |> Enum.join("")

      first <> cmds
    else
      ""
    end
  end

  defp amp_to_one(amp) do
    if is_number(amp) do
      positive = amp - @floor
      zero_to_one = positive / abs(@floor)
      min(max(zero_to_one, 0.0), 1.0)
    else
      0.0
    end
  end

  defp r(float) do
    :erlang.float_to_binary(float, decimals: 2)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="reveal-holder"
      class="absolute top-0 left-0 w-screen h-screen z-index-50"
      phx-update="ignore"
    >
      <div class="reveal" style="width: 100vw;">
        <div class="slides">
          <section data-markdown>
            <textarea data-template>
    ## Lively Membranes

    <img src="/underjord.svg">

    Mostly functional programming.


    ---

    ## Since the 90s

    - Self-taught developer, grew up doing web dev
    - Mixing technically interesting work with visually interesting work
    - Driven by realizing ideas, implementation, not theory
    - Are cool things naturally hard to do? Or are hard things simply cool?
    - Always new trouble in execution

    ---

    ## A theory of cool

    - Take input, transform it, produce interesting output
    - Strive for something novel
    - CRUD ain't it, chief

    ---

    ## Why Elixir?

    - Great for dealing with inputs.
    - Simple ways of dealing with state.
    - Does not require a bunch of extra infrastructure
    - LiveView made it incredible for building expressive outputs.
    - Wiring inputs to outputs could not be easier.

    <div class="flex gap-4">
    <div><img src="/elixir.png" class="bg-white p-4 rounded-md w-[200px]" /></div>
    <div><img src="/erlang.svg" class="bg-white p-4 rounded-md w-[200px]" /></div>
    <div><img src="/phoenix.png" class="p-4" /></div>
    </div>

    ---

    ## Inputs & Outputs

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

    <div><img src="/membrane.svg" class="bg-white p-4 rounded-md w-[600px]" /></div>

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
    - Interpreting transcript to offer voice commands
    - Everything is messages to a LiveView

    ---

    ## Questions?

    - Any questions about how this works is welcome.
    - Suggestions on what you'd like to see as I grow the talk, also welcome :)
    - Follow my stuff on underjord.io (newsletter, blog, YouTube, Mastodon, podcasts)

    <img src="/underjord.svg">

    Mostly functional programming.

    ---

    </textarea>
          </section>
        </div>
      </div>
    </div>
    <!-- Video as background -->
    <div
      id="video-bg"
      class="absolute top-0 left-0 w-screen h-screen overflow-hidden z-index-10"
      phx-update="ignore"
    >
      <video
        class="absolute top-0 left-0 w-screen h-screen object-cover z-index-1"
        id="video-preview"
        phx-hook="video"
        autoplay
      >
      </video>
      <svg
        id="the-svg"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 1600 900"
        stroke-width="7"
        stroke="currentColor"
        class="absolute top-0 right-0 stroke-white opacity-[0.15] overflow-hidden"
        preserveAspectRatio="xMinYMin slice"
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
    <div class="absolute min-w-full min-h-[48px] bottom-0 right-0 text-right overflow-hidden flex flex-nowrap bg-black text-white opacity-70 justify-end z-index-60 text-5xl mb-4">
      <span
        :for={{{start, _stop, text}, index} <- @transcripts |> Enum.with_index() |> Enum.take(-50)}
        class="inline-block mr-2 whitespace-nowrap"
        id={"transcription-#{index}"}
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
      <span
        :for={{text, i} <- @instants |> Enum.reject(&is_nil/1) |> Enum.with_index() |> Enum.reverse()}
        class="inline-block mr-1 whitespace-nowrap animate-pulse"
        id={"instant-#{i}"}
      >
        <div class="flex text-xs text-gray-400 gap-4">
          <span>&nbsp;</span>
        </div>
        <div>
          <%= text %>
        </div>
      </span>
    </div>
    """
  end
end
