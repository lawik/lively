defmodule LivelyWeb.AudioChannel do
  use LivelyWeb, :channel

  @impl true
  def join("audio:lobby", _payload, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("microphone_input", {:binary, payload}, socket) do
    Phoenix.PubSub.broadcast!(Lively.PubSub, "mic-input", {:payload, payload})
    {:noreply, socket}
  end
end
