defmodule LivelyWeb.MediaLive do
  use LivelyWeb, :live_view

  alias Lively.Media.Sample
  alias Lively.Media.Pipeline
  alias Lively.Media.Change

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
        level_flip?: true,
        hack?: false,
        change_path: "priv/alts/change_3.exs"
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
  def handle_event("show-hack", _, socket) do
    socket = assign(socket, hack?: not socket.assigns.hack?)
    {:noreply, socket}
  end

  @impl true
  def handle_event("execute", %{"code" => code}, socket) do
    path = "/tmp/change.ex"
    File.write!(path, code)
    Code.compile_string(code)
    {:noreply, assign(socket, change_path: path, hack?: false)}
  end

  @impl true
  def handle_event(other, params, socket) do
    IO.inspect({other, params}, label: "event")
    {:noreply, socket}
  end

  defp slide_titles do
    %{
      "do since the nineties" => 1,
      "do since the 90s" => 1,
      "a theory of cool software" => 2,
      "what does qualify as cool" => 3,
      "why do that in" => 4,
      "why would you do that in" => 4,
      "examples of inputs and outputs" => 5,
      "examples of input and output" => 5,
      "membrane enter the picture" => 6,
      "unpack transformations a bit" => 7,
      "unpack transformations a little bit" => 7,
      "a new way of transforming" => 8,
      "important to manage the complexity" => 9,
      "important to manage that complexity" => 9,
      "unpack this presentation a bit" => 10,
      "thank you for your time" => 11
    }
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
      case Enum.find(slide_titles(), fn {t, _} ->
             String.contains?(lower, t)
           end) do
        nil ->
          socket

        {_, sl} ->
          socket
          |> assign(slide: sl)
          |> push_event("go-to-slide", %{slide: sl})
      end

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

    if String.contains?(lower, "disable waveform") or
         String.contains?(lower, "disable the waveform") do
      Code.compile_file("lib/lively/media/change.ex")
    end

    if String.contains?(lower, "enable waveform") or
         String.contains?(lower, "enable the waveform") do
      Code.compile_file("priv/alts/change_1.exs")
    end

    if String.contains?(lower, "fancy waveform") do
      Code.compile_file("priv/alts/change_2.exs")
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

  @impl true
  def render(assigns) do
    ~H"""
    <div id="hack-holder" class="absolute top-4 right-4 bg-gray" style="z-index: 200;">
      <button class="text-white cursor-pointer" phx-click="show-hack">...</button>
    </div>
    <%= if assigns[:hack?] do %>
      <form
        id="hack-form"
        phx-submit="execute"
        class="absolute top-0 left-0 bg-transparent w-screen h-screen p-4"
        style="z-index: 199;"
      >
        <textarea
          class="hack-editor bg-transparent text-white text-2xl w-screen opacity-1"
          style="height: calc(100vh - 128px);"
          name="code"
        ><%= File.read!(@change_path) %></textarea>
        <button class="execute">Execute!</button>
      </form>
    <% end %>
    <div
      id="reveal-holder"
      class="absolute top-0 left-0 w-screen h-screen z-index-50"
      style={
        if @hack? do
          "display: none;"
        else
          ""
        end
      }
    >
      <div id="reveal-proper" class="reveal" style="width: 100vw;" phx-update="ignore">
        <div class="slides">
          <section data-markdown>
            <textarea data-template>
    ## Lively Membranes

    <img src="/underjord.svg">

    Mostly functional programming.

    <img class="" src="https://underjord.io/assets/images/team-thin.jpg" />


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

    ## What qualifies as cool?

    <div class="flex flex-full">

    <div class="">

    - Contextual, eye of the beholder
    - Not too hard, not too easy
    - The value of chasing shiny things
    - Effortless cool is built on practice
    - Cool is a motivator
    - Constraints and challenges

    </div>

    <div class="ml-auto flex-grow">
      <pre><code data-trim data-noescape>
      //.. part of generating a waveform
      amount..0
      |&gt; Enum.flat_map(fn index -&gt;
        Map.get(levels, index, [])
      end)
      |&gt; Enum.concat(for _ &lt;- 1..@use_samples, do: @floor)
      |&gt; Enum.take(@use_samples)
      |&gt; Enum.reverse()
      // more code on github.com/lawik/lively
      </code></pre>
    </div>

    </div>

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

    <div class="flex flex-full">

    <div class="">

    - Provides new Inputs and Outputs with audio and video
    - Traditionally difficult mediums to work with
    - Performs operations in Elixir, minimize shelling out
    - ffmpeg is rough to integrate with
    - Makes the results practical to use in Elixir
    - Make the actual process accessible in Elixir
    - More information than you might think

    <div><img src="/membrane.svg" class="bg-white p-4 rounded-md w-[600px]" /></div>

    </div>

    <div class="ml-auto flex-grow">
      <pre><code data-trim data-noescape>
      //.. part of a Membrane pipeline
      children = %{
        mic: %Lively.Media.PubSubSource{channel: "mic-input"},
        levels: %Membrane.Audiometer.Peakmeter{},
        timestamper: %MembraneTranscription.Timestamper{},
        instant_transcription: %MembraneTranscription.Element{
          buffer_duration: 1
        },
        transcription: %MembraneTranscription.Element{
          buffer_duration: 5
        },
        fake_out: Membrane.Fake.Sink.Buffers
      }
      // more code on github.com/lawik/lively
      </code></pre>
    </div>

    </div>

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

    ## Thank you

    - Questions are welcome in the hallway track.
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
    <div id="video-bg" class="absolute top-0 left-0 w-screen h-screen overflow-hidden z-index-10">
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
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d={Change.levels_to_draw_commands(@levels)}
        />
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
    <div
      class="absolute min-w-full min-h-[48px] bottom-0 right-0 text-right overflow-hidden flex flex-nowrap bg-black text-white opacity-70 justify-end z-index-60 text-5xl pb-4"
      style="z-index: 51;"
    >
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
