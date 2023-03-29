defmodule Lively.Media.PubSubSource do
  use Membrane.Source

  def_options(
    channel: [
      spec: :any,
      default: nil,
      description: "Channel that will be subscribed to."
    ],
    module: [
      spec: :any,
      default: nil,
      description: "PubSub module to use."
    ]
  )

  def_output_pad(:output,
    availability: :always,
    mode: :push,
    caps: {Membrane.RawAudio, sample_format: :f32le, channels: 1}
  )

  @initial_buffer 256
  @max_buffer 1
  @chunk_to 2048

  @impl true
  def handle_init(%__MODULE{channel: channel, module: module}) do
    Phoenix.PubSub.subscribe(module, channel)

    {:ok, %{buffers: [], demand_left: 0, live?: true}}
  end

  @impl true
  def handle_other({:payload, payload}, %{playback_state: :playing}, state) do
    # IO.inspect(byte_size(payload), label: "incoming")

    # if byte_size(payload) == @chunk_to do
    #   [%Membrane.Buffer{payload: payload} | state.buffers]
    # else
    #   payload
    #   |> chunk()
    #   |> Enum.reduce(state.buffers, fn chunk, bufs ->
    #     [%Membrane.Buffer{payload: chunk} | bufs]
    #   end)
    # end
    buffers = [%Membrane.Buffer{payload: payload} | state.buffers]

    # buffers =
    #   if Enum.count(buffers) > @max_buffer do
    #     buffers
    #     |> Enum.take(-@max_buffer)
    #   else
    #     buffers
    #   end

    # state = %{state | buffers: buffers}
    # {actions, state} = send_demand(state, 1)
    actions = [buffer: {:output, buffers}]
    state = %{state | buffers: []}
    # IO.inspect(Enum.count(buffers), label: "sending")
    # IO.inspect(actions)
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:payload, payload}, _ctx, state) do
    # buffers = [%Membrane.Buffer{payload: payload} | state.buffers]

    # buffers =
    #   if Enum.count(buffers) > @max_buffer do
    #     buffers
    #     |> Enum.take(-@max_buffer)
    #   else
    #     buffers
    #   end

    # state = %{state | buffers: buffers}
    {:ok, state}
  end

  defp chunk(binary, chunks \\ [])

  defp chunk(<<>>, chunks) do
    Enum.reverse(chunks)
  end

  defp chunk(<<ch::binary-size(@chunk_to), rest::binary>>, chunks) do
    chunk(rest, [ch | chunks])
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    {
      {:ok,
       caps: {
         :output,
         %Membrane.RawAudio{sample_format: :f32le, sample_rate: 16000, channels: 1}
       }},
      state
    }
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, []}, state}
  end

  defp send_demand(state, size) do
    live? = state.live? or Enum.count(state.buffers) > @initial_buffer

    if live? do
      # IO.inspect({state.demand_left, size}, label: "demanded buffers")
      demand = max(state.demand_left + size, 0)

      {take, keep} =
        state.buffers
        |> Enum.reverse()
        |> Enum.split(demand)

      taken = Enum.count(take)

      # IO.inspect(taken, label: "sending buffers")

      demand_left = max(demand - taken, 0)

      actions =
        if taken == 0 do
          # IO.inspect("sending no buffer")
          []
        else
          [buffer: {:output, take}]
        end

      {actions, %{state | buffers: keep, demand_left: demand_left, live?: live?}}
    else
      IO.inspect(Enum.count(state.buffers), label: "buffered")
      {[], state}
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    IO.puts("Handle playing to prepared")
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    IO.puts("Ending Map element")
    {:ok, state}
  end
end
