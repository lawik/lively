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
    mode: :pull,
    caps: :any
  )

  @impl true
  def handle_init(%__MODULE{channel: channel, module: module}) do
    Phoenix.PubSub.subscribe(module, channel)
    {:ok, %{buffer: nil}}
  end

  @impl true
  def handle_other({:payload, payload}, _ctx, state) do
    buffer = %Membrane.Buffer{payload: payload}
    state = %{state | buffer: buffer}
    {{:ok, []}, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, []}, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    actions =
      if state.buffer do
        [buffer: {:output, state.buffer}]
      else
        []
      end

    {{:ok, actions}, %{state | buffer: nil}}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _context, state) do
    actions =
      if state.buffer do
        [bytes: {:output, state.buffer}]
      else
        []
      end

    {{:ok, actions}, %{state | buffer: nil}}
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
