defmodule Chip8.Renderer do
  @callback render(display :: %{tuple() => non_neg_integer()}) :: :ok
end
