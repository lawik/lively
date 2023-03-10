defmodule Lively.Media.Sample do
  @episode_url "https://aphid.fireside.fm/d/1437767933/a11633b3-cf22-42b6-875e-ecdfee41c919/3f7a247d-9937-4cf1-8d5f-5a12e0bb1c09.mp3"
  @filepath Path.join(:code.priv_dir(:lively), "samples/intro.mp3")

  File.mkdir_p!(Path.dirname(@filepath))

  def get_path do
    case File.stat(@filepath) do
      {:error, :enoent} ->
        {:ok, result} = Req.get(@episode_url)
        File.write!(@filepath, result.body)

      {:ok, _} ->
        nil
    end

    @filepath
  end
end
