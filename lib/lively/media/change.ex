defmodule Lively.Media.Change do
  @height 600
  @width 1600
  @use_samples 150
  # @use_samples 100
  @floor -60
  @padding 150

  def levels_to_draw_commands(levels) do
    ""
  end

  def levels_to_draw_commands_1(levels) do
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
          "M#{ro(point * i * 2)} #{ro(top_y)}v#{ro(size)}"
        end)
        |> Enum.join("")

      # |> IO.inspect()

      # IO.puts("")

      cmds
    else
      ""
    end
  end

  def levels_to_draw_commands_2(levels) do
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
            "M0 #{ro(a * @height)}"

          [] ->
            ""
        end

      cmds =
        level
        |> Enum.with_index()
        |> Enum.map(fn {amp, i} ->
          a = amp_to_one(amp)
          # IO.inspect(a * @height)
          "L#{ro(point * i)} #{ro(@height - a * @height)}"
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

  defp ro(float) do
    :erlang.float_to_binary(float, decimals: 2)
  end
end
