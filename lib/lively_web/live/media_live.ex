defmodule LivelyWeb.MediaLive do
  use LivelyWeb, :live_view

  alias Lively.Media.Sample
  alias Lively.Media.Pipeline

  def mount(_session, _params, socket) do
    Phoenix.PubSub.subscribe(Lively.PubSub, "transcripts")
    socket = assign(socket, pipeline: nil, transcripts: [], levels: %{}, slide: 1)
    # DEV mode
    if connected?(socket) do
      {:noreply, socket} = play_pause("5", "mic", socket)
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
          {num, _} -> assign(socket, slide: num)
        end
      else
        socket
      end

    socket =
      if String.contains?(lower, "slide forward") do
        assign(socket, slide: socket.assigns.slide + 1)
      else
        socket
      end

    socket =
      if String.contains?(lower, "slide back") do
        assign(socket, slide: socket.assigns.slide - 1)
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
  defp levels_to_draw_commands(levels) do
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

  defp amp_to_one(minus_hundred) do
    (abs(minus_hundred) + 50) / 100
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
    <div><%= @slide %></div>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 1600 900"
            stroke-width="4"
            stroke="currentColor"
            class="absolute top-0 left-0 stroke-white opacity-25"
            preserveAspectRatio="xMidYMin slice"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d={levels_to_draw_commands(@levels)}
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
