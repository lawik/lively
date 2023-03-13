defmodule Lively.Media.Pipeline do
  use Membrane.Pipeline

  @target_sample_rate 16000
  @bitdepth 32
  @byte_per_sample @bitdepth / 8
  @byte_per_second @target_sample_rate * @byte_per_sample

  @impl true
  def handle_init(opts) do
    source = Keyword.fetch!(opts, :source)
    to_pid = Keyword.fetch!(opts, :to_pid)
    buffer_duration = Keyword.fetch!(opts, :buffer_duration)

    {init_link_fn, source_children} =
      case source do
        {:file, filepath} ->
          {
            fn ->
              link(:file)
              |> to(:decoder)
            end,
            %{
              file: %Membrane.File.Source{location: filepath},
              decoder: Membrane.MP3.MAD.Decoder
            }
          }

        :mic ->
          {
            fn ->
              link(:mic)
            end,
            %{
              mic: %Membrane.PortAudio.Source{endpoint_id: :default}
            }
          }
      end

    children =
      %{
        levels: %Membrane.Audiometer.Peakmeter{},
        converter: %Membrane.FFmpeg.SWResample.Converter{
          output_caps: %Membrane.RawAudio{
            sample_format: :f32le,
            sample_rate: @target_sample_rate,
            channels: 1
          }
        },
        timestamper: %MembraneTranscription.Timestamper{
          bytes_per_second: @byte_per_second
        },
        transcription: %MembraneTranscription.Element{
          buffer_duration: buffer_duration,
          fancy?: true
        },
        # better_transcription: %MembraneTranscription.Element{
        #   buffer_duration: 10
        # },
        fake_out: Membrane.Fake.Sink.Buffers
      }
      |> Map.merge(source_children)

    links = [
      init_link_fn.()
      |> to(:converter)
      |> to(:timestamper)
      |> to(:levels)
      |> to(:transcription)
      # |> to(:better_transcription)
      |> to(:fake_out)
    ]

    IO.puts("setup done")

    {{:ok, spec: %ParentSpec{children: children, links: links}, playback: :playing},
     %{to_pid: to_pid}}
  end

  @impl true
  def handle_shutdown(_reason, _state) do
    :ok
  end

  @impl true
  def handle_notification(
        {:transcribed, %{results: [%{text: text}]}, part, start, stop},
        _element,
        _context,
        state
      ) do
    Phoenix.PubSub.broadcast!(
      Lively.PubSub,
      "transcripts",
      {:transcribed, text, part, start, stop}
    )

    {:ok, state}
  end

  @impl true
  def handle_notification(
        {:amplitudes, amps},
        _element,
        _context,
        state
      ) do
    Phoenix.PubSub.broadcast!(
      Lively.PubSub,
      "transcripts",
      {:levels, amps}
    )

    {:ok, state}
  end

  @impl true
  def handle_notification(notification, element, _context, state) do
    IO.inspect(notification, label: "notification")
    IO.inspect(element, label: "element")
    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream({:fake_out, :input}, _context, state) do
    send(state.to_pid, :done)
    terminate(self())
    {{:ok, playback: :stopped}, state}
  end

  @impl true
  def handle_element_end_of_stream({:transcription, :input}, _context, state) do
    send(state.to_pid, :transcription_done)
    {{:ok, playback: :stopped}, state}
  end

  @impl true
  def handle_element_end_of_stream(_, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(_context, state) do
    {:ok, state}
  end

  @impl true
  def handle_other(:stop, _context, state) do
    {{:ok, playback: :stopped}, state}
  end
end
