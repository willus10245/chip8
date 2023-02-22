defmodule Chip8.Renderer.Text do
  @behaviour Chip8.Renderer

  @impl Chip8.Renderer
  def render(display) do
    pixels = for y <- 0..31, x <- 0..63, do: display[{x, y}]
    
    pixels
    |> Enum.map(fn 
      0 -> " "
      1 -> "X"
    end)
    |> Enum.chunk_every(64)
    |> Enum.map(&Enum.join/1)
    |> Enum.join("\n")
    |> IO.puts
  end
end
